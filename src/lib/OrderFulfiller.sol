// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ItemType, OrderType} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {AccumulatorStruct, FractionData, OrderToExecute} from "../reference/ConsiderationStructs.sol";

import {
    AdvancedOrder,
    ConsiderationItem,
    CriteriaResolver,
    OfferItem,
    OrderParameters,
    ReceivedItem,
    SpentItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {BasicOrderFulfiller} from "./BasicOrderFulfiller.sol";

import {CriteriaResolution} from "./CriteriaResolution.sol";

import {AmountDeriver} from "./AmountDeriver.sol";

import {
    _revertInsufficientNativeTokensSupplied,
    _revertInvalidNativeOfferItem
} from "seaport-types/src/lib/ConsiderationErrors.sol";

import {
    AccumulatorDisarmed,
    ConsiderationItem_recipient_offset,
    ReceivedItem_amount_offset,
    ReceivedItem_recipient_offset
} from "seaport-types/src/lib/ConsiderationConstants.sol";

/**
 * @title OrderFulfiller
 * @author 0age
 * @notice OrderFulfiller contains logic related to order fulfillment where a
 *         single order is being fulfilled and where basic order fulfillment is
 *         not available as an option.
 */
contract OrderFulfiller is BasicOrderFulfiller, CriteriaResolution, AmountDeriver {
    /**
     * @dev Derive and set hashes, reference chainId, and associated domain
     *      separator during deployment.
     *
     * @param conduitController A contract that deploys conduits, or proxies
     *                          that may optionally be used to transfer approved
     *                          ERC20/721/1155 tokens.
     */
    constructor(address conduitController) BasicOrderFulfiller(conduitController) {}

    /**
     * @dev Internal function to validate an order and update its status, adjust
     *      prices based on current time, apply criteria resolvers, determine
     *      what portion to fill, and transfer relevant tokens.
     *
     * @param advancedOrder       The order to fulfill as well as the fraction
     *                            to fill. Note that all offer and consideration
     *                            components must divide with no remainder for
     *                            the partial fill to be valid.
     * @param criteriaResolvers   An array where each element contains a
     *                            reference to a specific offer or
     *                            consideration, a token identifier, and a proof
     *                            that the supplied token identifier is
     *                            contained in the order's merkle root. Note
     *                            that a criteria of zero indicates that any
     *                            (transferable) token identifier is valid and
     *                            that no proof needs to be supplied.
     * @param fulfillerConduitKey A bytes32 value indicating what conduit, if
     *                            any, to source the fulfiller's token approvals
     *                            from. The zero hash signifies that no conduit
     *                            should be used, with direct approvals set on
     *                            Consideration.
     * @param recipient           The intended recipient for all received items.
     *
     * @return A boolean indicating whether the order has been fulfilled.
     */
    function _validateAndFulfillAdvancedOrder(
        AdvancedOrder memory advancedOrder,
        CriteriaResolver[] memory criteriaResolvers,
        bytes32 fulfillerConduitKey,
        address recipient
    ) internal returns (bool) {
        // Validate order, update status, and determine fraction to fill.
        (bytes32 orderHash, uint256 fillNumerator, uint256 fillDenominator) =
            _validateOrderAndUpdateStatus(advancedOrder, true);

        // Create an array with length 1 containing the order.
        AdvancedOrder[] memory advancedOrders = new AdvancedOrder[](1);

        // Populate the order as the first and only element of the new array.
        advancedOrders[0] = advancedOrder;

        // Apply criteria resolvers using generated orders and details arrays.
        _applyCriteriaResolvers(advancedOrders, criteriaResolvers);

        // Retrieve the order parameters after applying criteria resolvers.
        OrderParameters memory orderParameters = advancedOrders[0].parameters;

        // Perform each item transfer with the appropriate fractional amount.
        OrderToExecute memory orderToExecute = _applyFractionsAndTransferEach(
            orderParameters, 
            fillNumerator, 
            fillDenominator, 
            fulfillerConduitKey, 
            recipient
        );

        // Declare empty bytes32 array and populate with the order hash.
        bytes32[] memory orderHashes = new bytes32[](1);
        orderHashes[0] = orderHash;

        // Ensure restricted orders have a valid submitter or pass a zone check.
        _assertRestrictedAdvancedOrderValidity(
            advancedOrder,
            orderToExecute,
            orderHashes,
            orderHash,
            orderParameters.zoneHash,
            orderParameters.orderType,
            orderParameters.offerer,
            orderParameters.zone
        );

        // Emit an event signifying that the order has been fulfilled.
        _emitOrderFulfilledEvent(
            orderHash,
            orderParameters.offerer,
            orderParameters.zone,
            recipient,
            orderParameters.offer,
            orderParameters.consideration
        );

        return true;
    }

    /**
     * @dev Internal function to transfer each item contained in a given single
     *      order fulfillment after applying a respective fraction to the amount
     *      being transferred.
     *
     * @param orderParameters     The parameters for the fulfilled order.
     * @param numerator           A value indicating the portion of the order
     *                            that should be filled.
     * @param denominator         A value indicating the total order size.
     * @param fulfillerConduitKey A bytes32 value indicating what conduit, if
     *                            any, to source the fulfiller's token approvals
     *                            from. The zero hash signifies that no conduit
     *                            should be used (and direct approvals set on
     *                            Consideration).
     * @param recipient           The intended recipient for all received items.
     * @return orderToExecute     Returns the order of items that are being
     *                            transferred. This will be used for the
     *                            OrderFulfilled Event.
     */
    function _applyFractionsAndTransferEach(
        OrderParameters memory orderParameters,
        uint256 numerator,
        uint256 denominator,
        bytes32 fulfillerConduitKey,
        address recipient
    ) internal returns (OrderToExecute memory orderToExecute) {
        // Create the accumulator struct.
        AccumulatorStruct memory accumulatorStruct;

        // Get the offerer of the order.
        address offerer = orderParameters.offerer;

        // Get the conduitKey of the order
        bytes32 conduitKey = orderParameters.conduitKey;

        // Create the array to store the spent items for event.
        orderToExecute.spentItems = new SpentItem[](
            orderParameters.offer.length
        );

        // Declare a nested scope to minimize stack depth.
        {
            // Iterate over each offer on the order.
            for (uint256 i = 0; i < orderParameters.offer.length; ++i) {
                // Retrieve the offer item.
                OfferItem memory offerItem = orderParameters.offer[i];

                // Offer items for the native token can not be received outside
                // of a match order function except as part of a contract order.
                if (
                    offerItem.itemType == ItemType.NATIVE &&
                    orderParameters.orderType != OrderType.CONTRACT
                ) {
                    revert InvalidNativeOfferItem();
                }

                // Apply fill fraction to derive offer item amount to transfer.
                uint256 amount = _applyFraction(
                    offerItem.startAmount,
                    offerItem.endAmount,
                    numerator,
                    denominator,
                    orderParameters.startTime,
                    orderParameters.endTime,
                    false
                );

                // Create Received Item from Offer Item for transfer.
                ReceivedItem memory receivedItem = ReceivedItem(
                    offerItem.itemType,
                    offerItem.token,
                    offerItem.identifierOrCriteria,
                    amount,
                    payable(recipient)
                );

                // Create Spent Item for the OrderFulfilled event.
                orderToExecute.spentItems[i] = SpentItem(
                    receivedItem.itemType,
                    receivedItem.token,
                    receivedItem.identifier,
                    amount
                );

                // Transfer the item from the offerer to the recipient.
                _transfer(receivedItem, offerer, conduitKey, accumulatorStruct);
            }
        }

        // Create the array to store the received items for event.
        orderToExecute.receivedItems = new ReceivedItem[](
            orderParameters.consideration.length
        );

        // Declare a nested scope to minimize stack depth.
        {
            // Iterate over each consideration on the order.
            for (uint256 i = 0; i < orderParameters.consideration.length; ++i) {
                // Retrieve the consideration item.
                ConsiderationItem memory considerationItem = (
                    orderParameters.consideration[i]
                );

                // Apply fraction & derive considerationItem amount to transfer.
                uint256 amount = _applyFraction(
                    considerationItem.startAmount,
                    considerationItem.endAmount,
                    numerator,
                    denominator,
                    orderParameters.startTime,
                    orderParameters.endTime,
                    true
                );

                // Create Received Item from Offer item.
                ReceivedItem memory receivedItem = ReceivedItem(
                    considerationItem.itemType,
                    considerationItem.token,
                    considerationItem.identifierOrCriteria,
                    amount,
                    considerationItem.recipient
                );
                // Add ReceivedItem to structs array.
                orderToExecute.receivedItems[i] = receivedItem;

                if (receivedItem.itemType == ItemType.NATIVE) {
                    // Ensure that sufficient native tokens are still available.
                    if (amount > address(this).balance) {
                        revert InsufficientNativeTokensSupplied();
                    }
                }

                // Transfer item from caller to recipient specified by the item.
                _transfer(
                    receivedItem,
                    msg.sender,
                    fulfillerConduitKey,
                    accumulatorStruct
                );
            }
        }

        // Trigger any remaining accumulated transfers via call to the conduit.
        _triggerIfArmed(accumulatorStruct);

        // If any native token remains after fulfillments...
        if (address(this).balance != 0) {
            // return it to the caller.
            _transferNativeTokens(payable(msg.sender), address(this).balance);
        }
        // Return the order to execute.
        return orderToExecute;
    }

    /**
     * @dev Internal function to emit an OrderFulfilled event. OfferItems are
     *      translated into SpentItems and ConsiderationItems are translated
     *      into ReceivedItems.
     *
     * @param orderHash     The order hash.
     * @param offerer       The offerer for the order.
     * @param zone          The zone for the order.
     * @param recipient     The recipient of the order, or the null address if
     *                      the order was fulfilled via order matching.
     * @param offer         The offer items for the order.
     * @param consideration The consideration items for the order.
     */
    function _emitOrderFulfilledEvent(
        bytes32 orderHash,
        address offerer,
        address zone,
        address recipient,
        OfferItem[] memory offer,
        ConsiderationItem[] memory consideration
    ) internal {
        // Cast already-modified offer memory region as spent items.
        SpentItem[] memory spentItems;
        assembly {
            spentItems := offer
        }

        // Cast already-modified consideration memory region as received items.
        ReceivedItem[] memory receivedItems;
        assembly {
            receivedItems := consideration
        }

        // Emit an event signifying that the order has been fulfilled.
        emit OrderFulfilled(orderHash, offerer, zone, recipient, spentItems, receivedItems);
    }
}
