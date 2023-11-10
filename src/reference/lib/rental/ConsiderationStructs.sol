// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { ItemType, OrderType } from "seaport-types/src/lib/ConsiderationEnums.sol";

import {
    ReceivedItem,
    SpentItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import { ConduitTransfer } from "seaport-types/src/conduit/lib/ConduitStructs.sol";


/**
 * @dev Restricted orders are validated post-execution by calling validateOrder
 *      on the zone. This struct provides context about the order fulfillment
 *      and any supplied extraData, as well as all order hashes fulfilled in a
 *      call to a match or fulfillAvailable method.
 */
struct ZoneParameters {
    bytes32 orderHash;
    address fulfiller;
    address offerer;
    SpentItem[] offer;
    ReceivedItem[] consideration;
    ReceivedItem[] totalExecutions;
    bytes extraData;
    bytes32[] orderHashes;
    uint256 startTime;
    uint256 endTime;
    bytes32 zoneHash;
}