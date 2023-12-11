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

import {ZoneInteraction} from "src/lib/ZoneInteraction.sol";

import {Zone} from "test/helpers/Zone.sol";

contract ZoneInteraction_Test is Test, ZoneInteraction {

    Zone public zone;
    Vm.Wallet public wallet;

    function setUp() public {
        zone = new Zone();
        wallet = vm.createWallet("wallet");
    }

    function test_Success_AssertRestrictedAdvancedOrderValidity() public {

        // create offer
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({
            itemType: ItemType.ERC20,
            token: address(uint160(uint256(keccak256(abi.encode("erc20"))))),
            identifierOrCriteria: 9,
            startAmount: 150,
            endAmount: 150
        });
   
        // create consideration
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: address(uint160(uint256(keccak256(abi.encode("erc721"))))),
            identifierOrCriteria: 5,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(address(uint160(uint256(keccak256(abi.encode("recipient"))))))
        });

        // create the order parameters
        OrderParameters memory orderParameters = OrderParameters({
            offerer: wallet.addr,
            zone: address(zone),
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

        // create the advanced order
        AdvancedOrder memory advancedOrder = AdvancedOrder({
            parameters: orderParameters,
            numerator: 1,
            denominator: 1,
            signature: "signature",
            extraData: "extraData"
        });

        // create the order hash
        bytes32 orderHash = keccak256("order hash");

        // create the order hashes
        bytes32[] memory orderHashes = new bytes32[](1);
        orderHashes[0] = orderHash;
        
        // make a call to the zone
        _assertRestrictedAdvancedOrderValidity(
            advancedOrder,
            orderHashes,
            orderHash
        );

        assertEq(orderHash, zone.orderHash());

    }
}