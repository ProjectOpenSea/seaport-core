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
    OfferItem,
    Execution
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {OrderType, ItemType} from "seaport-types/src/lib/ConsiderationEnums.sol";
import {CalldataPointer, getFreeMemoryPointer, MemoryPointer} from "seaport-types/src/helpers/PointerLibraries.sol";

import {OrderCombinerHarness} from "test/harnesses/OrderCombinerHarness.sol";
import {StructPointers} from "src/lib/rental/ConsiderationStructs.sol";
import {ConduitController} from "src/conduit/ConduitController.sol";

import {Utils} from "test/helpers/Utils.sol";
import {Assertions} from "test/helpers/Assertions.sol";
import {Zone} from "test/helpers/Zone.sol";

import "forge-std/console.sol";

// Seaport performs checks to make sure tokens are contracts
contract MockToken {}

contract OrderCombiner_Test is Assertions {
    address mockConduitController;
    address mockERC20;
    address mockERC721;
    address mockOfferer;
    address mockRecipient;

    OrderCombinerHarness orderCombiner;
    Zone public zone;

    function setUp() public {
        // set mock addresses
        mockOfferer = Utils.mockAddress("offerer");
        mockRecipient = Utils.mockAddress("recipient");
        mockConduitController = Utils.mockAddress("conduitController");
        mockERC20 = address(new MockToken());
        mockERC721 = address(new MockToken());

        // mock a setup call to the conduit controller
        vm.mockCall(
            mockConduitController,
            abi.encodeWithSelector(ConduitController.getConduitCodeHashes.selector),
            abi.encode(bytes32(0), bytes32(0))
        );

        orderCombiner = new OrderCombinerHarness(mockConduitController);
        zone = new Zone();

        vm.label(address(orderCombiner), "orderCombiner");
        vm.label(mockERC20, "mockERC20");
        vm.label(mockERC721, "mockERC721");
    }

    function test_Success_PerformFinalChecksAndExecuteOrders() public {
        // create offer
        OfferItem[] memory offer = new OfferItem[](2);
        offer[0] = OfferItem({
            itemType: ItemType.ERC20,
            token: mockERC20,
            identifierOrCriteria: 0,
            startAmount: 0,
            endAmount: 150
        });
        offer[1] = OfferItem({
            itemType: ItemType.ERC20,
            token: mockERC20,
            identifierOrCriteria: 0,
            startAmount: 0,
            endAmount: 160
        });

        // create another offer which will not have a matching consideration
        OfferItem[] memory unmatchedOffer = new OfferItem[](2);
        offer[0] = OfferItem({
            itemType: ItemType.ERC20,
            token: mockERC20,
            identifierOrCriteria: 0,
            startAmount: 200,
            endAmount: 200
        });
   
        // create consideration
        ConsiderationItem[] memory consideration = new ConsiderationItem[](2);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: mockERC721,
            identifierOrCriteria: 5,
            startAmount: 0,
            endAmount: uint256(1),
            recipient: payable(mockOfferer)
        });
        consideration[1] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: mockERC721,
            identifierOrCriteria: 6,
            startAmount: 0,
            endAmount: uint256(1),
            recipient: payable(mockOfferer)
        });

        // create the order parameters
        OrderParameters memory orderParameters = OrderParameters({
            offerer: mockOfferer,
            zone: address(zone),
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

        // create a second order parameter struct
        OrderParameters memory secondOrderParameters = OrderParameters({
            offerer: mockOfferer,
            zone: address(zone),
            offer: unmatchedOffer,
            consideration: new ConsiderationItem[](0),
            orderType: OrderType.FULL_RESTRICTED,
            startTime: block.timestamp,
            endTime: block.timestamp + 5,
            zoneHash: keccak256("zone hash"),
            salt: 123456789,
            conduitKey: bytes32(0),
            totalOriginalConsiderationItems: 0
        }); 

        // create the advanced order array
        AdvancedOrder[] memory advancedOrders = new AdvancedOrder[](2);
        advancedOrders[0] = AdvancedOrder({
            parameters: orderParameters,
            numerator: 1,
            denominator: 1,
            signature: "signature",
            extraData: "extraData"
        });
        advancedOrders[1] = AdvancedOrder({
            parameters: secondOrderParameters,
            numerator: 1,
            denominator: 1,
            signature: "signature",
            extraData: "extraData"
        });

        // create the executions array
        Execution[] memory executions = new Execution[](4);
        executions[0] = Execution({
            item: ReceivedItem({
                itemType: offer[0].itemType,
                token: offer[0].token,
                identifier: offer[0].identifierOrCriteria,
                amount: offer[0].endAmount,
                recipient: payable(mockRecipient)
            }),
            offerer: mockOfferer,
            conduitKey: bytes32(0)
        });
        executions[1] = Execution({
            item: ReceivedItem({
                itemType: offer[1].itemType,
                token: offer[1].token,
                identifier: offer[1].identifierOrCriteria,
                amount: offer[1].endAmount,
                recipient: payable(mockRecipient)
            }),
            offerer: mockOfferer,
            conduitKey: bytes32(0)
        });
        executions[2] = Execution({
            item: ReceivedItem({
                itemType: consideration[0].itemType,
                token: consideration[0].token,
                identifier: consideration[0].identifierOrCriteria,
                amount: consideration[0].endAmount,
                recipient: payable(mockOfferer)
            }),
            offerer: mockRecipient,
            conduitKey: bytes32(0)
        });
        executions[3] = Execution({
            item: ReceivedItem({
                itemType: consideration[1].itemType,
                token: consideration[1].token,
                identifier: consideration[1].identifierOrCriteria,
                amount: consideration[1].endAmount,
                recipient: payable(mockOfferer)
            }),
            offerer: mockRecipient,
            conduitKey: bytes32(0)
        });


        // create the order hashes
        bytes32[] memory orderHashes = new bytes32[](2);
        orderHashes[0] = keccak256("order hash");
        orderHashes[1] = keccak256("order hash 2");

        // mock a transferFrom() call for the ERC20
        vm.mockCall(
            mockERC20,
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)"))),
            abi.encode(true)
        );
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
        vm.mockCall(
            mockERC721,
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)"))),
            abi.encode(true)
        );
        vm.mockCall(
            mockERC721,
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)"))),
            abi.encode(true)
        );

        // call the order combiner. Mark this contract as the recipient 
        // of any unspent offer items
        orderCombiner.performFinalChecksAndExecuteOrders(
            advancedOrders,
            executions,
            orderHashes,
            address(this),
            true
        );

        // create an expected executions array which contains all the received items
    }
}