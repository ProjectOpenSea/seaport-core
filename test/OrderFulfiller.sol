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

import "forge-std/console.sol";

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
        expectedExecutions[0] = ReceivedItem({
            itemType: offer[0].itemType,
            token: offer[0].token,
            identifier: offer[0].identifierOrCriteria,
            amount: offer[0].startAmount,
            recipient: payable(address(this))
        });
        expectedExecutions[1] = ReceivedItem({
            itemType: offer[1].itemType,
            token: offer[1].token,
            identifier: offer[1].identifierOrCriteria,
            amount: offer[1].startAmount,
            recipient: payable(address(this))
        });
        expectedExecutions[2] = ReceivedItem({
            itemType: consideration[0].itemType,
            token: consideration[0].token,
            identifier: consideration[0].identifierOrCriteria,
            amount: consideration[0].startAmount,
            recipient: payable(address(this))
        });
        expectedExecutions[3] = ReceivedItem({
            itemType: consideration[1].itemType,
            token: consideration[1].token,
            identifier: consideration[1].identifierOrCriteria,
            amount: consideration[1].startAmount,
            recipient: payable(address(this))
        });

        // create the order parameters
        OrderParameters memory orderParameters = OrderParameters({
            offerer: address(0x6666666666666666666666666666666666666666),
            zone: address(0x7777777777777777777777777777777777777777),
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