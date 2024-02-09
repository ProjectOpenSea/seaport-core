// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SpentItem, ReceivedItem, OrderType} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {ZoneParameters} from "src/lib/rental/ConsiderationStructs.sol";

contract Zone {

    // public valuues to test against
    bytes32 public orderHash;
    address public fulfiller;
    address public offerer;
    SpentItem[] public offer;
    ReceivedItem[] public consideration;
    ReceivedItem[] private _totalExecutions;
    bytes public extraData;
    bytes32[] public orderHashes;
    uint256 public startTime;
    uint256 public endTime;
    bytes32 public zoneHash;
    OrderType public orderType;
  
    function validateOrder(ZoneParameters calldata zoneParams) external returns (bytes4 validOrderMagicValue) {

        // store all zone parameters
        orderHash = zoneParams.orderHash;
        fulfiller = zoneParams.fulfiller;
        offerer = zoneParams.offerer;
        extraData = zoneParams.extraData;
        orderHashes = zoneParams.orderHashes;
        startTime = zoneParams.startTime;
        endTime = zoneParams.endTime;
        zoneHash = zoneParams.zoneHash;
        orderType = zoneParams.orderType;

        // push all offer items
        for (uint256 i; i < zoneParams.offer.length; ++i) {
            offer.push(zoneParams.offer[i]);
        }

        // push all consideration items
        for (uint256 i = 0; i < zoneParams.consideration.length; ++i) {
            consideration.push(zoneParams.consideration[i]);
        }

        // push all execution items
        for (uint256 i = 0; i < zoneParams.totalExecutions.length; ++i) {
            _totalExecutions.push(zoneParams.totalExecutions[i]);
        }

        // return the selector
        validOrderMagicValue = Zone.validateOrder.selector;
    }

    function totalExecutions() external view returns (ReceivedItem[] memory items) {
        return _totalExecutions;
    }
}