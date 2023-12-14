// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ItemType} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {
    ReceivedItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

abstract contract Assertions is Test {
    // Compares two `ItemType` enum entities
    function assertEq(ItemType a, ItemType b) internal {
        assertEq(uint256(a), uint256(b), "itemType");
    }

    // Compares two `ReceivedItem` struct entities
    function assertEq(ReceivedItem memory a, ReceivedItem memory b) internal {
        assertEq(a.itemType, b.itemType);
        assertEq(a.token, b.token, "token");
        assertEq(a.amount, b.amount, "amount");
        assertEq(a.identifier, b.identifier, "identifier");
        assertEq(a.recipient, b.recipient, "recipient");
    }

    // Compares two `ReceivedItem[]` struct entities
    function assertEq(ReceivedItem[] memory a, ReceivedItem[] memory b) internal {
        assertEq(a.length, b.length, "length mismatch");

        for (uint256 i = 0; i < a.length; ++i) {
            assertEq(a[0], b[0]);
        }
    }
}