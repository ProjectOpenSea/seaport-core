// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {Test} from "forge-std/Test.sol";
import {
    AdvancedOrder, 
    OrderParameters, 
    ZoneParameters, 
    SpentItem, 
    ReceivedItem,
    ConsiderationItem,
    OfferItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {OrderType, ItemType} from "seaport-types/src/lib/ConsiderationEnums.sol";
import {CalldataPointer, getFreeMemoryPointer, MemoryPointer} from "seaport-types/src/helpers/PointerLibraries.sol";

import {ConsiderationEncoder} from "src/lib/ConsiderationEncoder.sol";
import {StructPointers} from "src/lib/rental/ConsiderationStructs.sol";

import {Utils} from "test/helpers/Utils.sol";

contract ConsiderationEncoder_Test is Test, ConsiderationEncoder {

    function test_Success_EncodeValidateOrder() public {
        // create offer
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({
            itemType: ItemType.ERC20,
            token:  Utils.mockAddress("ERC20"),
            identifierOrCriteria: 9,
            startAmount: 150,
            endAmount: 150
        });
   
        // create consideration
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: Utils.mockAddress("ERC721"),
            identifierOrCriteria: 5,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(Utils.mockAddress("recipient"))
        });

        // convert the consideration items into received items silently
        Utils.convertConsiderationIntoReceivedItem(consideration);

        // create total executions 
        ReceivedItem[] memory totalExecutions = new ReceivedItem[](2);
        totalExecutions[0] = ReceivedItem({
            itemType: ItemType.ERC721,
            token: Utils.mockAddress("ERC721"),
            identifier: 5,
            amount: 1,
            recipient: payable(Utils.mockAddress("recipient"))
        });
        totalExecutions[1] = ReceivedItem({
            itemType: ItemType.ERC20,
            token: Utils.mockAddress("ERC20"),
            identifier: 9,
            amount: 150,
            recipient: payable(Utils.mockAddress("recipient"))
        });

        // create the order parameters
        OrderParameters memory orderParameters = OrderParameters({
            offerer: Utils.mockAddress("offerer"),
            zone: Utils.mockAddress("zone"),
            offer: offer,
            consideration: consideration,
            orderType: OrderType.FULL_RESTRICTED,
            startTime: block.timestamp,
            endTime: block.timestamp + 5,
            zoneHash: keccak256("zone hash"),
            salt: 123456789,
            conduitKey: keccak256("conduit key"),
            totalOriginalConsiderationItems: 1
        }); 

        // create the order hash
        bytes32 orderHash = keccak256("order hash");

        // create the order hashes
        bytes32[] memory orderHashes = new bytes32[](1);
        orderHashes[0] = orderHash;

        _encodeValidateOrder(
            orderHash,
            totalExecutions,
            orderParameters,
            bytes("extra data"),
            orderHashes
        );   

        assertTrue(true);   
    }
}