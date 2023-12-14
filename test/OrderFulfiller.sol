// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
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

import {OrderFulfillerHarness} from "test/harnesses/OrderFulfillerHarness.sol";
import {StructPointers} from "src/lib/rental/ConsiderationStructs.sol";
import {ConduitController} from "src/conduit/ConduitController.sol";

import {Utils} from "test/helpers/Utils.sol";
import {Assertions} from "test/helpers/Assertions.sol";

// Seaport performs checks to make sure tokens are contracts
contract MockToken {}

contract OrderFulfiller_Test is Assertions {
    address mockConduitController;
    address mockERC20;
    address mockERC721;

    OrderFulfillerHarness orderFulfiller;

    function setUp() public {
        // set mock addresses
        mockConduitController = Utils.mockAddress("conduitController");
        mockERC20 = address(new MockToken());
        mockERC721 = address(new MockToken());

        // mock a setup call to the conduit controller
        vm.mockCall(
            mockConduitController,
            abi.encodeWithSelector(ConduitController.getConduitCodeHashes.selector),
            abi.encode(bytes32(0), bytes32(0))
        );

        orderFulfiller = new OrderFulfillerHarness(mockConduitController);

        vm.label(address(orderFulfiller), "orderFulfiller");
        vm.label(mockERC20, "mockERC20");
        vm.label(mockERC721, "mockERC721");
    }

    function test_Success_ApplyFractionsAndTransferEach() public {
        // create offer
        OfferItem[] memory offer = new OfferItem[](2);
        offer[0] = OfferItem({
            itemType: ItemType.ERC20,
            token: mockERC20,
            identifierOrCriteria: 0,
            startAmount: 150,
            endAmount: 150
        });
        offer[1] = OfferItem({
            itemType: ItemType.ERC20,
            token: mockERC20,
            identifierOrCriteria: 0,
            startAmount: 160,
            endAmount: 160
        });
   
        // create consideration
        ConsiderationItem[] memory consideration = new ConsiderationItem[](2);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: mockERC721,
            identifierOrCriteria: 5,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(address(this))
        });
        consideration[1] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: mockERC721,
            identifierOrCriteria: 6,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(address(this))
        });

        // convert the consideration items into received items silently
        Utils.convertConsiderationIntoReceivedItem(consideration);

        // create expected executions 
        ReceivedItem[] memory expectedExecutions = new ReceivedItem[](4);
        for (uint256 i = 0; i < expectedExecutions.length; ++i) {
            if (i < offer.length) {
                OfferItem memory offerItem = offer[i];
                expectedExecutions[i] = ReceivedItem({
                    itemType: offerItem.itemType,
                    token: offerItem.token,
                    identifier: offerItem.identifierOrCriteria,
                    amount: offerItem.startAmount,
                    recipient: payable(address(this))
                });
            } else {
                ConsiderationItem memory considerationItem = consideration[i - offer.length];
                expectedExecutions[i] = ReceivedItem({
                    itemType: considerationItem.itemType,
                    token: considerationItem.token,
                    identifier: considerationItem.identifierOrCriteria,
                    amount: considerationItem.startAmount,
                    recipient: payable(address(this))
                });
            }
        }

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
            conduitKey: bytes32(0),
            totalOriginalConsiderationItems: 1
        });

        // mock a transferFrom() call for the ERC20
        vm.mockCall(
            mockERC20,
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)"))),
            abi.encode(true)
        );

        // mock a transferFrom() call for the ERC721
        vm.mockCall(
            mockERC721,
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)"))),
            abi.encode(true)
        );
        
        // get the outputted executions
        ReceivedItem[] memory executions = orderFulfiller.applyFractionsAndTransferEach(
            orderParameters,
            1,
            1,
            bytes32(0), // dont use conduit key to perform transfer directly
            address(this)
        );

        assertEq(expectedExecutions, executions);
    }
}