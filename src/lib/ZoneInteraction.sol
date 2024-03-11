// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrderType } from "seaport-types/src/lib/ConsiderationEnums.sol";

import {
    AdvancedOrder,
    BasicOrderParameters,
    OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {
    ZoneInteractionErrors
} from "seaport-types/src/interfaces/ZoneInteractionErrors.sol";

import { LowLevelHelpers } from "./LowLevelHelpers.sol";

import { ConsiderationEncoder } from "./ConsiderationEncoder.sol";

import {
    CalldataPointer,
    MemoryPointer,
    OffsetOrLengthMask,
    ZeroSlotPtr
} from "seaport-types/src/helpers/PointerLibraries.sol";

import {
    authorizeOrder_selector_offset,
    BasicOrder_zone_cdPtr,
    ContractOrder_orderHash_offerer_shift,
    MaskOverFirstFourBytes,
    OneWord,
    OrderParameters_salt_offset,
    OrderParameters_zone_offset,
    validateOrder_selector_offset
} from "seaport-types/src/lib/ConsiderationConstants.sol";

import {
    Error_selector_offset,
    InvalidContractOrder_error_selector,
    InvalidRestrictedOrder_error_length,
    InvalidRestrictedOrder_error_orderHash_ptr,
    InvalidRestrictedOrder_error_selector
} from "seaport-types/src/lib/ConsiderationErrorConstants.sol";

/**
 * @title ZoneInteraction
 * @author 0age
 * @notice ZoneInteraction contains logic related to interacting with zones.
 */
contract ZoneInteraction is
    ConsiderationEncoder,
    ZoneInteractionErrors,
    LowLevelHelpers
{
    /**
     * @dev Internal function to determine if an order has a restricted order
     *      type and, if so, to ensure that either the zone is the caller or
     *      that a call to `validateOrder` on the zone returns a magic value
     *      indicating that the order is currently valid. Note that contract
     *      orders are not accessible via the basic fulfillment method.
     *
     * @param orderHash  The hash of the order.
     * @param orderType  The order type.
     */
    function _assertRestrictedBasicOrderAuthorization(
        bytes32 orderHash,
        OrderType orderType
    ) internal returns (uint256 callDataPointer) {
        // Order type 2-3 require zone be caller or zone to approve.
        // Note that in cases where fulfiller == zone, the restricted order
        // validation will be skipped.
        if (
            _isRestrictedAndCallerNotZone(
                orderType,
                CalldataPointer.wrap(BasicOrder_zone_cdPtr).readAddress()
            )
        ) {
            // Encode the `authorizeOrder` call in memory.
            (
                MemoryPointer callData,
                uint256 size,
                uint256 memoryLocationForOrderHashes
            ) = _encodeAuthorizeBasicOrder(orderHash);

            // Write the error selector to memory at the zero slot where it can
            // be used to revert with a specific error message.
            ZeroSlotPtr.write(InvalidRestrictedOrder_error_selector);

            // Perform `authorizeOrder` call & ensure magic value was returned.
            _callAndCheckStatus(
                CalldataPointer.wrap(BasicOrder_zone_cdPtr).readAddress(),
                orderHash,
                callData.offset(authorizeOrder_selector_offset),
                size
            );

            // Restore the zero slot.
            ZeroSlotPtr.write(0);

            // Register the calldata pointer for the encoded calldata.
            callDataPointer = MemoryPointer.unwrap(callData);

            // Utilize unchecked logic as size value cannot be so large as to
            // cause an overflow.
            unchecked {
                // Write the packed encoding of size and memory location for
                // order hashes to memory at the head of the encoded calldata.
                callData.write(
                    ((size + OneWord) << 128) | memoryLocationForOrderHashes
                );
            }
        }
    }

    /**
     * @dev Internal function to determine if an order has a restricted order
     *      type and, if so, to ensure that either the zone is the caller or
     *      that a call to `validateOrder` on the zone returns a magic value
     *      indicating that the order is currently valid. Note that contract
     *      orders are not accessible via the basic fulfillment method.
     *
     * @param orderHash   The hash of the order.
     * @param orderType   The order type.
     * @param callDataPtr The pointer to the call data for the basic order.
     *                    Note that the initial value will contain the size
     *                    and the memory location for order hashes length.
     */
    function _assertRestrictedBasicOrderValidity(
        bytes32 orderHash,
        OrderType orderType,
        uint256 callDataPtr
    ) internal {
        // Order type 2-3 require zone be caller or zone to approve.
        // Note that in cases where fulfiller == zone, the restricted order
        // validation will be skipped.
        if (
            _isRestrictedAndCallerNotZone(
                orderType,
                CalldataPointer.wrap(BasicOrder_zone_cdPtr).readAddress()
            )
        ) {
            // Cast the call data pointer to a memory pointer.
            MemoryPointer callData = MemoryPointer.wrap(callDataPtr);

            // Retrieve the size and memory location for order hashes from the
            // head of the encoded calldata where it was previously written.
            uint256 sizeAndMemoryLocationForOrderHashes = (
                callData.readUint256()
            );

            // Split the packed encoding to retrieve size and memory location.
            uint256 size = sizeAndMemoryLocationForOrderHashes >> 128;
            uint256 memoryLocationForOrderHashes = (
                sizeAndMemoryLocationForOrderHashes & OffsetOrLengthMask
            );

            // Encode the `validateOrder` call in memory.
            _encodeValidateBasicOrder(callData, memoryLocationForOrderHashes);

            // Account for the offset of the selector in the encoded call data.
            callData = callData.offset(validateOrder_selector_offset);

            // Write the error selector to memory at the zero slot where it can
            // be used to revert with a specific error message.
            ZeroSlotPtr.write(InvalidRestrictedOrder_error_selector);

            // Perform `validateOrder` call and ensure magic value was returned.
            _callAndCheckStatus(
                CalldataPointer.wrap(BasicOrder_zone_cdPtr).readAddress(),
                orderHash,
                callData,
                size
            );

            // Restore the zero slot.
            ZeroSlotPtr.write(0);
        }
    }

    /**
     * @dev Internal function to determine the pre-execution validity of
     *      restricted orders, signaling whether or not the order is valid.
     *      Restricted orders where the caller is not the zone must
     *      successfully call `authorizeOrder` with the correct magic value
     *      returned.
     *
     * @param advancedOrder   The advanced order in question.
     * @param orderHashes     The order hashes of each order included as part
     *                        of the current fulfillment.
     * @param orderHash       The hash of the order.
     * @param orderIndex      The index of the order.
     * @param revertOnInvalid Whether to revert if the call is invalid.
     *
     * @return isValid True if the order is valid, false otherwise (unless
     *                 revertOnInvalid is true, in which case this function
     *                 will revert).
     */
    function _checkRestrictedAdvancedOrderAuthorization(
        AdvancedOrder memory advancedOrder,
        bytes32[] memory orderHashes,
        bytes32 orderHash,
        uint256 orderIndex,
        bool revertOnInvalid
    ) internal returns (bool isValid) {
        // Retrieve the parameters of the order in question.
        OrderParameters memory parameters = advancedOrder.parameters;

        // OrderType 2-3 require zone to be caller or approve via validateOrder.
        if (
            _isRestrictedAndCallerNotZone(parameters.orderType, parameters.zone)
        ) {
            // Encode the `validateOrder` call in memory.
            (MemoryPointer callData, uint256 size) = _encodeAuthorizeOrder(
                orderHash,
                parameters,
                advancedOrder.extraData,
                orderHashes,
                orderIndex
            );

            // Perform call and ensure a corresponding magic value was returned.
            return
                _callAndCheckStatusWithSkip(
                    parameters.zone,
                    orderHash,
                    callData,
                    size,
                    InvalidRestrictedOrder_error_selector,
                    revertOnInvalid
                );
        }

        return true;
    }

    /**
     * @dev Internal function to determine the pre-execution validity of
     *      restricted orders and to revert if the order is invalid.
     *      Restricted orders where the caller is not the zone must
     *      successfully call `authorizeOrder` with the correct magic value
     *      returned.
     *
     * @param advancedOrder   The advanced order in question.
     * @param orderHashes     The order hashes of each order included as part
     *                        of the current fulfillment.
     * @param orderHash       The hash of the order.
     * @param orderIndex      The index of the order.
     */
    function _assertRestrictedAdvancedOrderAuthorization(
        AdvancedOrder memory advancedOrder,
        bytes32[] memory orderHashes,
        bytes32 orderHash,
        uint256 orderIndex
    ) internal {
        // Retrieve the parameters of the order in question.
        OrderParameters memory parameters = advancedOrder.parameters;

        // OrderType 2-3 requires zone to call or approve via authorizeOrder.
        if (
            _isRestrictedAndCallerNotZone(parameters.orderType, parameters.zone)
        ) {
            // Encode the `authorizeOrder` call in memory.
            (MemoryPointer callData, uint256 size) = _encodeAuthorizeOrder(
                orderHash,
                parameters,
                advancedOrder.extraData,
                orderHashes,
                orderIndex
            );

            // Write the error selector to memory at the zero slot where it can
            // be used to revert with a specific error message.
            ZeroSlotPtr.write(InvalidRestrictedOrder_error_selector);

            // Perform call and ensure a corresponding magic value was returned.
            _callAndCheckStatus(parameters.zone, orderHash, callData, size);

            // Restore the zero slot.
            ZeroSlotPtr.write(0);
        }
    }

    /**
     * @dev Internal function to determine the post-execution validity of
     *      restricted and contract orders. Restricted orders where the caller
     *      is not the zone must successfully call `validateOrder` with the
     *      correct magic value returned. Contract orders must successfully call
     *      `ratifyOrder` with the correct magic value returned.
     *
     * @param advancedOrder The advanced order in question.
     * @param orderHashes   The order hashes of each order included as part of
     *                      the current fulfillment.
     * @param orderHash     The hash of the order.
     */
    function _assertRestrictedAdvancedOrderValidity(
        AdvancedOrder memory advancedOrder,
        bytes32[] memory orderHashes,
        bytes32 orderHash
    ) internal {
        // Declare variables that will be assigned based on the order type.
        address target;
        uint256 errorSelector;
        MemoryPointer callData;
        uint256 size;

        // Retrieve the parameters of the order in question.
        OrderParameters memory parameters = advancedOrder.parameters;

        // OrderType 2-3 require zone to be caller or approve via validateOrder.
        if (
            _isRestrictedAndCallerNotZone(parameters.orderType, parameters.zone)
        ) {
            // Encode the `validateOrder` call in memory.
            (callData, size) = _encodeValidateOrder(
                parameters
                    .toMemoryPointer()
                    .offset(OrderParameters_salt_offset)
                    .readUint256(),
                orderHashes
            );

            // Set the target to the zone.
            target = (
                parameters
                    .toMemoryPointer()
                    .offset(OrderParameters_zone_offset)
                    .readAddress()
            );

            // Set the restricted-order-specific error selector.
            errorSelector = InvalidRestrictedOrder_error_selector;
        } else if (parameters.orderType == OrderType.CONTRACT) {
            // Set the target to the offerer (note the offerer has no offset).
            target = parameters.toMemoryPointer().readAddress();

            // Shift the target 96 bits to the left.
            uint256 shiftedOfferer;
            assembly {
                shiftedOfferer := shl(
                    ContractOrder_orderHash_offerer_shift,
                    target
                )
            }

            // Encode the `ratifyOrder` call in memory.
            (callData, size) = _encodeRatifyOrder(
                orderHash,
                parameters,
                advancedOrder.extraData,
                orderHashes,
                shiftedOfferer
            );

            // Set the contract-order-specific error selector.
            errorSelector = InvalidContractOrder_error_selector;
        } else {
            return;
        }

        // Write the error selector to memory at the zero slot where it can be
        // used to revert with a specific error message.
        ZeroSlotPtr.write(errorSelector);

        // Perform call and ensure a corresponding magic value was returned.
        _callAndCheckStatus(target, orderHash, callData, size);

        // Restore the zero slot.
        ZeroSlotPtr.write(0);
    }

    /**
     * @dev Determines whether the specified order type is restricted and the
     *      caller is not the specified zone.
     *
     * @param orderType     The type of the order to check.
     * @param zone          The address of the zone to check against.
     *
     * @return mustValidate True if the order type is restricted and the caller
     *                      is not the specified zone, false otherwise.
     */
    function _isRestrictedAndCallerNotZone(
        OrderType orderType,
        address zone
    ) internal view returns (bool mustValidate) {
        // Utilize assembly to efficiently perform the check.
        assembly {
            mustValidate := and(
                // Note that this check requires that there are no order
                // types beyond the current set (0-4).  It will need to be
                // modified if more order types are added.
                and(lt(orderType, 4), gt(orderType, 1)),
                iszero(eq(caller(), zone))
            )
        }
    }

    /**
     * @dev Calls the specified target with the given data and checks the status
     *      of the call. Revert reasons will be "bubbled up" if one is returned,
     *      otherwise reverting calls will throw a generic error based on the
     *      supplied error handler. Note that the custom error selector must
     *      already be in memory at the zero slot when this function is called.
     *
     * @param target        The address of the contract to call.
     * @param orderHash     The hash of the order associated with the call.
     * @param callData      The data to pass to the contract call.
     * @param size          The size of calldata.
     */
    function _callAndCheckStatus(
        address target,
        bytes32 orderHash,
        MemoryPointer callData,
        uint256 size
    ) internal {
        bool success;
        bool magicMatch;
        assembly {
            // Get magic value from the selector at start of provided calldata.
            let magic := and(mload(callData), MaskOverFirstFourBytes)

            // Clear the start of scratch space.
            mstore(0, 0)

            // Perform call, placing result in the first word of scratch space.
            success := call(gas(), target, 0, callData, size, 0, OneWord)

            // Determine if returned magic value matches the calldata selector.
            magicMatch := eq(magic, mload(0))
        }

        // Revert if the call was not successful.
        if (!success) {
            // Revert and pass reason along if one was returned.
            _revertWithReasonIfOneIsReturned();

            // If no reason was returned, revert with supplied error selector.
            assembly {
                // The error selector is already in memory at the zero slot.
                mstore(0x80, orderHash)
                // revert(abi.encodeWithSelector(
                //     "InvalidRestrictedOrder(bytes32)",
                //     orderHash
                // ))
                revert(0x7c, InvalidRestrictedOrder_error_length)
            }
        }

        // Revert if the correct magic value was not returned.
        if (!magicMatch) {
            // Revert with a generic error message.
            assembly {
                // The error selector is already in memory at the zero slot.
                mstore(0x80, orderHash)
                // revert(abi.encodeWithSelector(
                //     "InvalidRestrictedOrder(bytes32)",
                //     orderHash
                // ))
                revert(0x7c, InvalidRestrictedOrder_error_length)
            }
        }
    }

    /**
     * @dev Calls the specified target with the given data and checks the status
     *      of the call. Revert reasons will be "bubbled up" if one is returned,
     *      otherwise reverting calls will throw a generic error based on the
     *      supplied error handler.
     *
     * @param target          The address of the contract to call.
     * @param orderHash       The hash of the order associated with the call.
     * @param callData        The data to pass to the contract call.
     * @param size            The size of calldata.
     * @param errorSelector   The error handling function to call if the call
     *                        fails or the magic value does not match.
     * @param revertOnInvalid Whether to revert if the call is invalid. Must
     *                        still revert if the call returns invalid data.
     */
    function _callAndCheckStatusWithSkip(
        address target,
        bytes32 orderHash,
        MemoryPointer callData,
        uint256 size,
        uint256 errorSelector,
        bool revertOnInvalid
    ) internal returns (bool) {
        bool success;
        bool magicMatch;
        assembly {
            // Get magic value from the selector at start of provided calldata.
            let magic := and(mload(callData), MaskOverFirstFourBytes)

            // Clear the start of scratch space.
            mstore(0, 0)

            // Perform call, placing result in the first word of scratch space.
            success := call(gas(), target, 0, callData, size, 0, OneWord)

            // Determine if returned magic value matches the calldata selector.
            magicMatch := eq(magic, mload(0))
        }

        // Revert or return false if the call was not successful.
        if (!success) {
            if (!revertOnInvalid) {
                return false;
            }

            // Revert and pass reason along if one was returned.
            _revertWithReasonIfOneIsReturned();

            // If no reason was returned, revert with supplied error selector.
            assembly {
                mstore(0, errorSelector)
                mstore(InvalidRestrictedOrder_error_orderHash_ptr, orderHash)
                // revert(abi.encodeWithSelector(
                //     "InvalidRestrictedOrder(bytes32)",
                //     orderHash
                // ))
                revert(
                    Error_selector_offset,
                    InvalidRestrictedOrder_error_length
                )
            }
        }

        // Revert if the correct magic value was not returned.
        if (!magicMatch) {
            // Revert with a generic error message.
            assembly {
                mstore(0, errorSelector)
                mstore(InvalidRestrictedOrder_error_orderHash_ptr, orderHash)

                // revert(abi.encodeWithSelector(
                //     "InvalidRestrictedOrder(bytes32)",
                //     orderHash
                // ))
                revert(
                    Error_selector_offset,
                    InvalidRestrictedOrder_error_length
                )
            }
        }

        return true;
    }
}
