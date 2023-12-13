// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {getFreeMemoryPointer, MemoryPointer} from "seaport-types/src/helpers/PointerLibraries.sol";
import {
    ReceivedItem,
    ConsiderationItem
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

    // function dumpMemory() internal pure {
    //     uint256 mSize;
    //     assembly { mSize := msize() }

    //     for (uint256 i = mSize; ; i -= 0x20) {
    //         assembly {
    //             mstore(add(i, 0x40), mload(i))
    //         }
    //         if (i == 0) break;
    //     }

    //     assembly {
    //         mstore(0, 0x20)
    //         mstore(0x20, mSize)
    //         return (0, msize())
    //     }
    // }

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

}