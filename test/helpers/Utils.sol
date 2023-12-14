// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {getFreeMemoryPointer, MemoryPointer} from "seaport-types/src/helpers/PointerLibraries.sol";
import {
    ReceivedItem,
    ConsiderationItem,
    OfferItem,
    Execution
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {
    ReceivedItem_amount_offset,
    ReceivedItem_recipient_offset, 
    ConsiderationItem_recipient_offset
} from "seaport-types/src/lib/ConsiderationConstants.sol";

library Utils {
    address private constant VM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm private constant vm = Vm(VM_ADDRESS);

    // converts a bytes object into a memory pointer
    function toMemoryPointer(bytes memory obj) internal pure returns (MemoryPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    // creates a mock address from a string
    function mockAddress(string memory addressString) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(addressString)))));
    }

    // In `_applyFractionsAndTransferEach`, the consideration items are silently 
    // converted into received items. This mimics that transformation.
    function convertConsiderationIntoReceivedItem(ConsiderationItem[] memory consideration) internal pure {
        for (uint256 i = 0; i < consideration.length; ++i) {
            // Retrieve the consideration item.
            ConsiderationItem memory considerationItem = consideration[i];

            // fetch the amount
            uint256 amount = considerationItem.startAmount;

            // Use assembly to set overloaded considerationItem arguments.
            assembly {
                // Write derived fractional amount to startAmount as amount.
                mstore(add(considerationItem, ReceivedItem_amount_offset), amount)

                // Write original recipient to endAmount as recipient.
                mstore(
                    add(considerationItem, ReceivedItem_recipient_offset),
                    mload(add(considerationItem, ConsiderationItem_recipient_offset))
                )
            }
        }
    }

    // Fetches the memory from a memory pointer with a specified size
    function fetchMemory(MemoryPointer currentPointer, uint256 size) internal pure returns (bytes memory data) {
        // fetch a pointer to the end of the memory
        MemoryPointer end = currentPointer.offset(size);

        // create a placeholder variable for the data
        MemoryPointer dataLengthPtr = toMemoryPointer(data);
        MemoryPointer currentData = toMemoryPointer(data).offset(0x20);

        // loop through the memory, one word at a time
        while (currentPointer.lt(end)) {
            // get the length
            uint256 length = dataLengthPtr.readUint256();

            // increase the length
            dataLengthPtr.writeBytes32(bytes32(length + 32));

            // write the value to the output data bytes value         
            currentData.writeBytes32(currentPointer.readBytes32());

            // increment pointers
            currentData = currentData.next();
            currentPointer = currentPointer.next();
        }

        return data;
    }
    
    function offerToExecution(
        OfferItem memory offer, 
        address offerer, 
        address recipient,
        bytes32 conduitKey
    ) internal pure returns (Execution memory execution) {
        execution = Execution({
            item: ReceivedItem({
                itemType: offer.itemType,
                token: offer.token,
                identifier: offer.identifierOrCriteria,
                amount: offer.endAmount,
                recipient: payable(recipient)
            }),
            offerer: offerer,
            conduitKey: conduitKey
        });
    }

    function considerationToExecution(
        ConsiderationItem memory consideration, 
        address offerer, 
        bytes32 conduitKey
    ) internal pure returns (Execution memory execution) {
        execution = Execution({
            item: ReceivedItem({
                itemType: consideration.itemType,
                token: consideration.token,
                identifier: consideration.identifierOrCriteria,
                amount: consideration.endAmount,
                recipient: consideration.recipient
            }),
            offerer: offerer,
            conduitKey: conduitKey
        });
    }

}