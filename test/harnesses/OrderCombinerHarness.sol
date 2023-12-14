// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {
    AdvancedOrder, 
    Execution
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {OrderCombiner} from "src/lib/OrderCombiner.sol";

contract OrderCombinerHarness is OrderCombiner {

    constructor(address conduitController) OrderCombiner(conduitController) {}

    function performFinalChecksAndExecuteOrders(
        AdvancedOrder[] memory advancedOrders,
        Execution[] memory executions,
        bytes32[] memory orderHashes,
        address recipient,
        bool containsNonOpen
    ) external returns (bool[] memory availableOrders) {
        availableOrders = _performFinalChecksAndExecuteOrders(
            advancedOrders, 
            executions, 
            orderHashes, 
            recipient, 
            containsNonOpen
        );
    } 
}