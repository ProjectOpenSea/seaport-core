// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {
    OrderParameters, 
    ReceivedItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {OrderFulfiller} from "src/lib/OrderFulfiller.sol";

contract OrderFulfillerHarness is OrderFulfiller {

    constructor(address conduitController) OrderFulfiller(conduitController) {}

    function applyFractionsAndTransferEach(
        OrderParameters memory orderParameters,
        uint256 numerator,
        uint256 denominator,
        bytes32 fulfillerConduitKey,
        address recipient
    ) external returns (ReceivedItem[] memory totalExecutions) {
        totalExecutions = _applyFractionsAndTransferEach(orderParameters, numerator, denominator, fulfillerConduitKey, recipient);
    }
}