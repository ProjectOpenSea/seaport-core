// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrderType } from "seaport-types/src/lib/ConsiderationEnums.sol";

import {
    AdvancedOrder,
    ConsiderationItem,
    OfferItem,
    Order,
    OrderComponents,
    OrderParameters,
    OrderStatus
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {
    _revertBadFraction,
    _revertCannotCancelOrder,
    _revertConsiderationLengthNotEqualToTotalOriginal,
    _revertInvalidContractOrder,
    _revertPartialFillsNotEnabledForOrder
} from "seaport-types/src/lib/ConsiderationErrors.sol";

import { Executor } from "./Executor.sol";

import { ZoneInteraction } from "./ZoneInteraction.sol";

import { MemoryPointer } from "seaport-types/src/helpers/PointerLibraries.sol";

import {
    AdvancedOrder_denominator_offset,
    AdvancedOrder_numerator_offset,
    BasicOrder_basicOrderParameters_cd_offset,
    BasicOrder_offerer_cdPtr,
    BasicOrder_signature_cdPtr,
    Common_amount_offset,
    Common_endAmount_offset,
    Common_identifier_offset,
    Common_token_offset,
    ConsiderItem_recipient_offset,
    ContractOrder_orderHash_offerer_shift,
    MaxUint120,
    OrderStatus_filledDenominator_offset,
    OrderStatus_filledNumerator_offset,
    OrderStatus_ValidatedAndNotCancelled,
    OrderStatus_ValidatedAndNotCancelledAndFullyFilled,
    ReceivedItem_recipient_offset
} from "seaport-types/src/lib/ConsiderationConstants.sol";

import {
    Error_selector_offset,
    Panic_arithmetic,
    Panic_error_code_ptr,
    Panic_error_length,
    Panic_error_selector
} from "seaport-types/src/lib/ConsiderationErrorConstants.sol";

import {
    CalldataPointer
} from "seaport-types/src/helpers/PointerLibraries.sol";

/**
 * @title OrderValidator
 * @author 0age
 * @notice OrderValidator contains functionality related to validating orders
 *         and updating their status.
 */
contract OrderValidator is Executor, ZoneInteraction {
    // Track status of each order (validated, cancelled, and fraction filled).
    mapping(bytes32 => OrderStatus) private _orderStatus;

    // Track nonces for contract offerers.
    mapping(address => uint256) internal _contractNonces;

    /**
     * @dev Derive and set hashes, reference chainId, and associated domain
     *      separator during deployment.
     *
     * @param conduitController A contract that deploys conduits, or proxies
     *                          that may optionally be used to transfer approved
     *                          ERC20/721/1155 tokens.
     */
    constructor(address conduitController) Executor(conduitController) { }

    /**
     * @dev Internal function to verify the status of a basic order.
     *      Note that this function may only be safely called as part of basic
     *      orders, as it assumes a specific calldata encoding structure that
     *      must first be validated.
     *
     * @param orderHash The hash of the order.
     */
    function _validateBasicOrder(               
        bytes32 orderHash
    ) internal view returns (OrderStatus storage orderStatus) {
        // Retrieve offerer directly using fixed calldata offset based on strict
        // basic parameter encoding.
        address offerer;
        assembly {
            offerer := calldataload(BasicOrder_offerer_cdPtr)
        }

        // Retrieve the order status for the given order hash.
        orderStatus = _orderStatus[orderHash];

        // Ensure order is fillable and is not cancelled.
        _verifyOrderStatus(
            orderHash,
            orderStatus,
            true, // Only allow unused orders when fulfilling basic orders.
            _runTimeConstantTrue() // Signifies to revert if order is invalid.
        );

        unchecked {
            // If the order is not already validated, verify supplied signature.
            if (!orderStatus.isValidated) {
                _verifySignature(
                    offerer,
                    orderHash,
                    _toBytesReturnType(_decodeBytes)(
                        // Wrap the absolute pointer to the order signature as a
                        // CalldataPointer.
                        CalldataPointer.wrap(
                            // Read the relative pointer to the order signature.
                            CalldataPointer
                                .wrap(BasicOrder_signature_cdPtr)
                                .readMaskedUint256() +
                                // Add the BasicOrderParameters struct offset to
                                // the relative pointer.
                                BasicOrder_basicOrderParameters_cd_offset
                        )
                    )
                );
            }
        }
    }

    /**
     * @dev Internal function to update the status of a basic order, assuming
     *      all validation has already been performed.
     *
     * @param orderStatus A storage pointer referencing the order status.
     */
    function _updateBasicOrderStatus(OrderStatus storage orderStatus) internal {
        // Utilize assembly to efficiently update the order status.
        assembly {
            // Update order status as validated, not cancelled, & fully filled.
            sstore(
                orderStatus.slot,
                OrderStatus_ValidatedAndNotCancelledAndFullyFilled
            )
        }  
    }

    /**
     * @dev Internal function to validate an order, determine what portion to
     *      fill, and update its status. The desired fill amount is supplied as
     *      a fraction, as is the returned amount to fill.
     *
     * @param advancedOrder     The order to fulfill as well as the fraction to
     *                          fill. Note that all offer and consideration
     *                          amounts must divide with no remainder in order
     *                          for a partial fill to be valid.
     * @param revertOnInvalid   A boolean indicating whether to revert if the
     *                          order is invalid due to the time or status.
     *
     * @return orderHash      The order hash.
     * @return numerator      A value indicating the portion of the order that
     *                        will be filled.
     * @return denominator    A value indicating the total size of the order.
     */
    function _validateOrder(
        AdvancedOrder memory advancedOrder,
        bool revertOnInvalid
    )
        internal
        view
        returns (bytes32 orderHash, uint256 numerator, uint256 denominator)
    {
        // Retrieve the parameters for the order.
        OrderParameters memory orderParameters = advancedOrder.parameters;

        // Ensure current timestamp falls between order start time and end time.
        if (
            !_verifyTime(
                orderParameters.startTime,
                orderParameters.endTime,
                revertOnInvalid
            )
        ) {
            // Assuming an invalid time and no revert, return zeroed out values.
            return (bytes32(0), 0, 0);
        }

        // Read numerator and denominator from memory and place on the stack.
        // Note that overflowed values are masked.
        assembly {
            numerator :=
                and(
                    mload(add(advancedOrder, AdvancedOrder_numerator_offset)),
                    MaxUint120
                )

            denominator :=
                and(
                    mload(add(advancedOrder, AdvancedOrder_denominator_offset)),
                    MaxUint120
                )
        }

        // Declare variable for tracking the validity of the supplied fraction.
        bool invalidFraction;

        // If the order is a contract order, return the generated order.
        if (orderParameters.orderType == OrderType.CONTRACT) {
            // Ensure that the numerator and denominator are both equal to 1.
            assembly {
                // (1 ^ nd =/= 0) => (nd =/= 1) => (n =/= 1) || (d =/= 1)
                // It's important that the values are 120-bit masked before
                // multiplication is applied. Otherwise, the last implication
                // above is not correct (mod 2^256).
                invalidFraction := xor(mul(numerator, denominator), 1)
            }

            // Revert if the supplied numerator and denominator are not valid.
            if (invalidFraction) {
                _revertBadFraction();
            }
            // Return a placeholder orderHash and a fill fraction of 1/1.
            // The real orderHash will be returned by _getGeneratedOrder.
            return (
                bytes32(uint256(1)), 1, 1
            );
        }

        // Ensure numerator does not exceed denominator and is not zero.
        assembly {
            invalidFraction := or(gt(numerator, denominator), iszero(numerator))
        }

        // Revert if the supplied numerator and denominator are not valid.
        if (invalidFraction) {
            _revertBadFraction();
        }

        // If attempting partial fill (n < d) check order type & ensure support.
        if (
            _doesNotSupportPartialFills(
                orderParameters.orderType, numerator, denominator
            )
        ) {
            // Revert if partial fill was attempted on an unsupported order.
            _revertPartialFillsNotEnabledForOrder();
        }

        // Retrieve current counter & use it w/ parameters to derive order hash.
        orderHash = _assertConsiderationLengthAndGetOrderHash(orderParameters);

        // Retrieve the order status using the derived order hash.
        OrderStatus storage orderStatus = _orderStatus[orderHash];

        // Ensure order is fillable and is not cancelled.
        if (
            // Allow partially used orders to be filled.
            !_verifyOrderStatus(orderHash, orderStatus, false, revertOnInvalid)
        ) {
            // Assuming an invalid order status and no revert, return zero fill.
            return (orderHash, 0, 0);
        }

        // If the order is not already validated, verify the supplied signature.
        if (!orderStatus.isValidated) {
            _verifySignature(
                orderParameters.offerer, orderHash, advancedOrder.signature
            );
        }

        // Utilize assembly to determine the fraction to fill and update status.
        assembly {
            let orderStatusSlot := orderStatus.slot
            // Read filled amount as numerator and denominator and put on stack.
            let filledNumerator := sload(orderStatusSlot)
            let filledDenominator :=
                shr(OrderStatus_filledDenominator_offset, filledNumerator)

            // "Loop" until the appropriate fill fraction has been determined.
            for { } 1 { } {
                // If no portion of the order has been filled yet...
                if iszero(filledDenominator) {
                    // fill the full supplied fraction.
                    filledNumerator := numerator

                    // Exit the "loop" early.
                    break
                }

                // Shift and mask to calculate the current filled numerator.
                filledNumerator :=
                    and(
                        shr(
                            OrderStatus_filledNumerator_offset,
                            filledNumerator
                        ),
                        MaxUint120
                    )

                // If denominator of 1 supplied, fill entire remaining amount.
                if eq(denominator, 1) {
                    // Set the amount to fill to the remaining amount.
                    numerator := sub(filledDenominator, filledNumerator)

                    // Set the fill size to the current size.
                    denominator := filledDenominator

                    // Exit the "loop" early.
                    break
                }

                // If supplied denominator is equal to the current one:
                if eq(denominator, filledDenominator) {
                    // Increment the filled numerator by the new numerator.
                    filledNumerator := add(numerator, filledNumerator)

                    // Once adjusted, if current + supplied numerator exceeds
                    // the denominator:
                    let carry :=
                        mul(
                            sub(filledNumerator, denominator),
                            gt(filledNumerator, denominator)
                        )

                    // reduce the amount to fill by the excess.
                    numerator := sub(numerator, carry)

                    // Exit the "loop" early.
                    break
                }

                // Otherwise, if supplied denominator differs from current one:
                // Scale the filled amount up by the supplied size.
                filledNumerator := mul(filledNumerator, denominator)

                // Scale the supplied amount and size up by the current size.
                numerator := mul(numerator, filledDenominator)
                denominator := mul(denominator, filledDenominator)

                // Increment the filled numerator by the new numerator.
                filledNumerator := add(numerator, filledNumerator)

                // Once adjusted, if current + supplied numerator exceeds
                // denominator:
                let carry :=
                    mul(
                        sub(filledNumerator, denominator),
                        gt(filledNumerator, denominator)
                    )

                // reduce the amount to fill by the excess.
                numerator := sub(numerator, carry)

                // Reduce the filled amount by the excess as well.
                filledNumerator := sub(filledNumerator, carry)

                // Check denominator for uint120 overflow.
                if gt(denominator, MaxUint120) {
                    // Derive greatest common divisor using euclidean algorithm.
                    function gcd(_a, _b) -> out {
                        // "Loop" until only one non-zero value remains.
                        for { } _b { } {
                            // Assign the second value to a temporary variable.
                            let _c := _b

                            // Derive the modulus of the two values.
                            _b := mod(_a, _c)

                            // Set the first value to the temporary value.
                            _a := _c
                        }

                        // Return the remaining non-zero value.
                        out := _a
                    }

                    // Determine the amount to scale down the fill fractions.
                    let scaleDown :=
                        gcd(numerator, gcd(filledNumerator, denominator))

                    // Ensure that the divisor is at least one.
                    let safeScaleDown := add(scaleDown, iszero(scaleDown))

                    // Scale fractional values down by gcd.
                    numerator := div(numerator, safeScaleDown)
                    denominator := div(denominator, safeScaleDown)

                    // Perform the overflow check a second time.
                    if gt(denominator, MaxUint120) {
                        // Store the Panic error signature.
                        mstore(0, Panic_error_selector)
                        // Store the arithmetic (0x11) panic code.
                        mstore(Panic_error_code_ptr, Panic_arithmetic)

                        // revert(abi.encodeWithSignature(
                        //     "Panic(uint256)", 0x11
                        // ))
                        revert(Error_selector_offset, Panic_error_length)
                    }
                }

                // Exit the "loop" now that all evaluation is complete.
                break
            }
        }
    }

    /**
     * @dev Internal function to update the status of an order by applying the
     *      supplied fill fraction to the remaining order fraction. If
     *      revertOnInvalid is true, the function will revert if the order is
     *      unavailable or if it is not possible to apply the supplied fill 
     *      fraction to the remaining amount (e.g., if there is not enough
     *      of the order remaining to fill the supplied fraction, or if the
     *      fractions cannot be represented by two uint120 values).
     * 
     * @param orderHash       The hash of the order.
     * @param numerator       The numerator of the fraction filled to write to
     *                        the order status.
     * @param denominator     The denominator of the fraction filled to write to
     *                        the order status.
     * @param revertOnInvalid Whether to revert if an order is already filled.
     */
    function _updateStatus(
        bytes32 orderHash,
        uint256 numerator,
        uint256 denominator,
        bool revertOnInvalid
    ) internal returns (bool) {
        // Retrieve the order status using the derived order hash.
        OrderStatus storage orderStatus = _orderStatus[orderHash];

        bool hasCarry = false;

        uint256 orderStatusSlot;
        uint256 filledNumerator;

        // Utilize assembly to determine the fraction to fill and update status.
        assembly {
            orderStatusSlot := orderStatus.slot
            // Read filled amount as numerator and denominator and put on stack.
            filledNumerator := sload(orderStatusSlot)
            let filledDenominator :=
                shr(OrderStatus_filledDenominator_offset, filledNumerator)

            // "Loop" until the appropriate fill fraction has been determined.
            for { } 1 { } {
                // If no portion of the order has been filled yet...
                if iszero(filledDenominator) {
                    // fill the full supplied fraction.
                    filledNumerator := numerator

                    // Exit the "loop" early.
                    break
                }

                // Shift and mask to calculate the current filled numerator.
                filledNumerator :=
                    and(
                        shr(
                            OrderStatus_filledNumerator_offset,
                            filledNumerator
                        ),
                        MaxUint120
                    )

                // If supplied denominator is equal to the current one:
                if eq(denominator, filledDenominator) {
                    // Increment the filled numerator by the new numerator.
                    filledNumerator := add(numerator, filledNumerator)

                    hasCarry := gt(filledNumerator, denominator)

                    // Exit the "loop" early.
                    break
                }

                // Otherwise, if supplied denominator differs from current one:
                // Scale the filled amount up by the supplied size.
                filledNumerator := mul(filledNumerator, denominator)

                // Scale the supplied amount and size up by the current size.
                numerator := mul(numerator, filledDenominator)
                denominator := mul(denominator, filledDenominator)

                // Increment the filled numerator by the new numerator.
                filledNumerator := add(numerator, filledNumerator)

                hasCarry := gt(filledNumerator, denominator)

                // Check filledNumerator and denominator for uint120 overflow.
                if or(
                    gt(filledNumerator, MaxUint120), gt(denominator, MaxUint120)
                ) {
                    // Derive greatest common divisor using euclidean algorithm.
                    function gcd(_a, _b) -> out {
                        // "Loop" until only one non-zero value remains.
                        for { } _b { } {
                            // Assign the second value to a temporary variable.
                            let _c := _b

                            // Derive the modulus of the two values.
                            _b := mod(_a, _c)

                            // Set the first value to the temporary value.
                            _a := _c
                        }

                        // Return the remaining non-zero value.
                        out := _a
                    }

                    // Determine amount to scale down the new filled fraction.
                    let scaleDown := gcd(filledNumerator, denominator)

                    // Ensure that the divisor is at least one.
                    let safeScaleDown := add(scaleDown, iszero(scaleDown))

                    // Scale new filled fractional values down by gcd.
                    filledNumerator := div(filledNumerator, safeScaleDown)
                    denominator := div(denominator, safeScaleDown)

                    // Perform the overflow check a second time.
                    if or(
                        gt(filledNumerator, MaxUint120),
                        gt(denominator, MaxUint120)
                    ) {
                        // Store the Panic error signature.
                        mstore(0, Panic_error_selector)
                        // Store the arithmetic (0x11) panic code.
                        mstore(Panic_error_code_ptr, Panic_arithmetic)

                        // revert(abi.encodeWithSignature(
                        //     "Panic(uint256)", 0x11
                        // ))
                        revert(Error_selector_offset, Panic_error_length)
                    }
                }

                // Exit the "loop" now that all evaluation is complete.
                break
            }
        }

        if (hasCarry) {
            if (revertOnInvalid) {
                revert OrderAlreadyFilled(orderHash);
            } else {
                return false;
            }
        }

        assembly {
            // Update order status and fill amount, packing struct values.
            // [denominator: 15 bytes] [numerator: 15 bytes]
            // [isCancelled: 1 byte] [isValidated: 1 byte]
            sstore(
                orderStatusSlot,
                or(
                    OrderStatus_ValidatedAndNotCancelled,
                    or(
                        shl(
                            OrderStatus_filledNumerator_offset,
                            filledNumerator
                        ),
                        shl(OrderStatus_filledDenominator_offset, denominator)
                    )
                )
            )
        }

        return true;
    }

    /**
     * @dev Internal function to generate a contract order. When a
     *      collection-wide criteria-based item (criteria = 0) is provided as an
     *      input to a contract order, the contract offerer has full latitude to
     *      choose any identifier it wants mid-flight, which differs from the
     *      usual behavior.  For regular criteria-based orders with
     *      identifierOrCriteria = 0, the fulfiller can pick which identifier to
     *      receive by providing a CriteriaResolver. For contract offers with
     *      identifierOrCriteria = 0, Seaport does not expect a corresponding
     *      CriteriaResolver, and will revert if one is provided.
     *
     * @param orderParameters The parameters for the order.
     * @param context         The context for generating the order.
     * @param revertOnInvalid Whether to revert on invalid input.
     *
     * @return orderHash   The order hash.
     */
    function _getGeneratedOrder(
        OrderParameters memory orderParameters,
        bytes memory context,
        bool revertOnInvalid
    )
        internal
        returns (bytes32 orderHash)
    {
        // Ensure that consideration array length is equal to the total original
        // consideration items value.
        if (
            orderParameters.consideration.length
                != orderParameters.totalOriginalConsiderationItems
        ) {
            _revertConsiderationLengthNotEqualToTotalOriginal();
        }

        {
            address offerer = orderParameters.offerer;
            bool success;
            (MemoryPointer cdPtr, uint256 size) =
                _encodeGenerateOrder(orderParameters, context);
            assembly {
                success := call(gas(), offerer, 0, cdPtr, size, 0, 0)
            }

            {
                // Note: overflow impossible; nonce can't increment that high.
                uint256 contractNonce;
                unchecked {
                    // Note: nonce will be incremented even for skipped orders,
                    // and even if generateOrder's return data does not satisfy
                    // all the constraints. This is the case when errorBuffer
                    // != 0 and revertOnInvalid == false.
                    contractNonce = _contractNonces[offerer]++;
                }

                assembly {
                    // Shift offerer address up 96 bytes and combine with nonce.
                    orderHash :=
                        xor(
                            contractNonce,
                            shl(ContractOrder_orderHash_offerer_shift, offerer)
                        )
                }
            }

            // Revert or skip if the call to generate the contract order failed.
            if (!success) {
                if (revertOnInvalid) {
                    _revertWithReasonIfOneIsReturned();

                    _revertInvalidContractOrder(orderHash);
                }

                return bytes32(0);
            }
        }

        // From this point onward, do not allow for skipping orders as the
        // contract offerer may have modified state in expectation of any named
        // consideration items being sent to their designated recipients.

        // Decode the returned contract order and/or update the error buffer.
        (
            uint256 errorBuffer,
            OfferItem[] memory offer,
            ConsiderationItem[] memory consideration
        ) = _convertGetGeneratedOrderResult(_decodeGenerateOrderReturndata)(
            orderParameters.offer, orderParameters.consideration
        );

        // Revert if the returndata could not be decoded correctly.
        if (errorBuffer != 0) {
            _revertInvalidContractOrder(orderHash);
        }

        // Assign the returned offer item in place of the original item.
        orderParameters.offer = offer;

        // Assign returned consideration item in place of the original item.
        orderParameters.consideration = consideration;

        // Return the order hash.
        return orderHash;
    }

    /**
     * @dev Internal function to cancel an arbitrary number of orders. Note that
     *      only the offerer or the zone of a given order may cancel it. Callers
     *      should ensure that the intended order was cancelled by calling
     *      `getOrderStatus` and confirming that `isCancelled` returns `true`.
     *      Also note that contract orders are not cancellable.
     *
     * @param orders The orders to cancel.
     *
     * @return cancelled A boolean indicating whether the supplied orders were
     *                   successfully cancelled.
     */
    function _cancel(OrderComponents[] calldata orders)
        internal
        returns (bool cancelled)
    {
        // Ensure that the reentrancy guard is not currently set.
        _assertNonReentrant();

        // Declare variables outside of the loop.
        OrderStatus storage orderStatus;

        // Declare a variable for tracking invariants in the loop.
        bool anyInvalidCallerOrContractOrder;

        // Skip overflow check as for loop is indexed starting at zero.
        unchecked {
            // Read length of the orders array from memory and place on stack.
            uint256 totalOrders = orders.length;

            // Iterate over each order.
            for (uint256 i = 0; i < totalOrders;) {
                // Retrieve the order.
                OrderComponents calldata order = orders[i];

                address offerer = order.offerer;
                address zone = order.zone;
                OrderType orderType = order.orderType;

                assembly {
                    // If caller is neither the offerer nor zone, or a contract
                    // order is present, flag anyInvalidCallerOrContractOrder.
                    anyInvalidCallerOrContractOrder :=
                        or(
                            anyInvalidCallerOrContractOrder,
                            // orderType == CONTRACT ||
                            // !(caller == offerer || caller == zone)
                            or(
                                eq(orderType, 4),
                                iszero(
                                    or(
                                        eq(caller(), offerer),
                                        eq(caller(), zone)
                                    )
                                )
                            )
                        )
                }

                bytes32 orderHash = _deriveOrderHash(
                    _toOrderParametersReturnType(
                        _decodeOrderComponentsAsOrderParameters
                    )(order.toCalldataPointer()),
                    order.counter
                );

                // Retrieve the order status using the derived order hash.
                orderStatus = _orderStatus[orderHash];

                // Update the order status as not valid and cancelled.
                orderStatus.isValidated = false;
                orderStatus.isCancelled = true;

                // Emit an event signifying that the order has been cancelled.
                emit OrderCancelled(orderHash, offerer, zone);

                // Increment counter inside body of loop for gas efficiency.
                ++i;
            }
        }

        if (anyInvalidCallerOrContractOrder) {
            _revertCannotCancelOrder();
        }

        // Return a boolean indicating that orders were successfully cancelled.
        cancelled = true;
    }

    /**
     * @dev Internal function to validate an arbitrary number of orders, thereby
     *      registering their signatures as valid and allowing the fulfiller to
     *      skip signature verification on fulfillment. Note that validated
     *      orders may still be unfulfillable due to invalid item amounts or
     *      other factors; callers should determine whether validated orders are
     *      fulfillable by simulating the fulfillment call prior to execution.
     *      Also note that anyone can validate a signed order, but only the
     *      offerer can validate an order without supplying a signature.
     *
     * @param orders The orders to validate.
     *
     * @return validated A boolean indicating whether the supplied orders were
     *                   successfully validated.
     */
    function _validate(Order[] memory orders)
        internal
        returns (bool validated)
    {
        // Ensure that the reentrancy guard is not currently set.
        _assertNonReentrant();

        // Declare variables outside of the loop.
        OrderStatus storage orderStatus;
        bytes32 orderHash;
        address offerer;

        // Skip overflow check as for loop is indexed starting at zero.
        unchecked {
            // Read length of the orders array from memory and place on stack.
            uint256 totalOrders = orders.length;

            // Iterate over each order.
            for (uint256 i = 0; i < totalOrders; ++i) {
                // Retrieve the order.
                Order memory order = orders[i];

                // Retrieve the order parameters.
                OrderParameters memory orderParameters = order.parameters;

                // Skip contract orders.
                if (orderParameters.orderType == OrderType.CONTRACT) {
                    continue;
                }

                // Move offerer from memory to the stack.
                offerer = orderParameters.offerer;

                // Get current counter & use it w/ params to derive order hash.
                orderHash =
                    _assertConsiderationLengthAndGetOrderHash(orderParameters);

                // Retrieve the order status using the derived order hash.
                orderStatus = _orderStatus[orderHash];

                // Ensure order is fillable and retrieve the filled amount.
                _verifyOrderStatus(
                    orderHash,
                    orderStatus,
                    false, // Signifies that partially filled orders are valid.
                    _runTimeConstantTrue() // Revert if order is invalid.
                );

                // If the order has not already been validated...
                if (!orderStatus.isValidated) {
                    // Ensure that consideration array length is equal to the
                    // total original consideration items value.
                    if (
                        orderParameters.consideration.length
                            != orderParameters.totalOriginalConsiderationItems
                    ) {
                        _revertConsiderationLengthNotEqualToTotalOriginal();
                    }

                    // Verify the supplied signature.
                    _verifySignature(offerer, orderHash, order.signature);

                    // Update order status to mark the order as valid.
                    orderStatus.isValidated = true;

                    // Emit an event signifying the order has been validated.
                    emit OrderValidated(orderHash, orderParameters);
                }
            }
        }

        // Return a boolean indicating that orders were successfully validated.
        validated = true;
    }

    /**
     * @dev Internal view function to retrieve the status of a given order by
     *      hash, including whether the order has been cancelled or validated
     *      and the fraction of the order that has been filled.
     *
     * @param orderHash The order hash in question.
     *
     * @return isValidated A boolean indicating whether the order in question
     *                     has been validated (i.e. previously approved or
     *                     partially filled).
     * @return isCancelled A boolean indicating whether the order in question
     *                     has been cancelled.
     * @return totalFilled The total portion of the order that has been filled
     *                     (i.e. the "numerator").
     * @return totalSize   The total size of the order that is either filled or
     *                     unfilled (i.e. the "denominator").
     */
    function _getOrderStatus(bytes32 orderHash)
        internal
        view
        returns (
            bool isValidated,
            bool isCancelled,
            uint256 totalFilled,
            uint256 totalSize
        )
    {
        // Retrieve the order status using the order hash.
        OrderStatus storage orderStatus = _orderStatus[orderHash];

        // Return the fields on the order status.
        return (
            orderStatus.isValidated,
            orderStatus.isCancelled,
            orderStatus.numerator,
            orderStatus.denominator
        );
    }

    /**
     * @dev Internal pure function to check whether a given order type indicates
     *      that partial fills are not supported (e.g. only "full fills" are
     *      allowed for the order in question).
     *
     * @param orderType   The order type in question.
     * @param numerator   The numerator in question.
     * @param denominator The denominator in question.
     *
     * @return isFullOrder A boolean indicating whether the order type only
     *                     supports full fills.
     */
    function _doesNotSupportPartialFills(
        OrderType orderType,
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (bool isFullOrder) {
        // The "full" order types are even, while "partial" order types are odd.
        // Bitwise and by 1 is equivalent to modulo by 2, but 2 gas cheaper. The
        // check is only necessary if numerator is less than denominator.
        assembly {
            // Equivalent to `uint256(orderType) & 1 == 0`.
            isFullOrder :=
                and(lt(numerator, denominator), iszero(and(orderType, 1)))
        }
    }
}
