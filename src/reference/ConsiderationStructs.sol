// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    ReceivedItem,
    SpentItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

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