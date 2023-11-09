// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    ReceivedItem,
    SpentItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import { ConduitTransfer } from "seaport-types/src/conduit/lib/ConduitStructs.sol";

/**
 * @dev A struct that is an explicit version of advancedOrders without
 *       memory optimization, that provides an array of spentItems
 *       and receivedItems for fulfillment and event emission.
 */
struct OrderToExecute {
    address offerer;
    SpentItem[] spentItems; // Offer
    ReceivedItem[] receivedItems; // Consideration
    bytes32 conduitKey;
    uint120 numerator;
    uint256[] spentItemOriginalAmounts;
    uint256[] receivedItemOriginalAmounts;
}

/**
 * @dev  A struct containing the data used to apply a
 *       fraction to an order.
 */
struct FractionData {
    uint256 numerator; // The portion of the order that should be filled.
    uint256 denominator; // The total size of the order
    bytes32 fulfillerConduitKey; // The fulfiller's conduit key.
    uint256 startTime; // The start time of the order.
    uint256 endTime; // The end time of the order.
}

/**
 * @dev A struct containing conduit transfer data and its
 *      corresponding conduitKey.
 */
struct AccumulatorStruct {
    bytes32 conduitKey;
    ConduitTransfer[] transfers;
}