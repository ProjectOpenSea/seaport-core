// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ConduitInterface} from "seaport-types/src/interfaces/ConduitInterface.sol";

import { ConduitTransfer } from "seaport-types/src/conduit/lib/ConduitStructs.sol";

import {ConduitItemType} from "seaport-types/src/conduit/lib/ConduitEnums.sol";

import {ItemType} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {Verifiers} from "./Verifiers.sol";

import {TokenTransferrer} from "./TokenTransferrer.sol";

import {AccumulatorStruct} from "../reference/ConsiderationStructs.sol";

import {
    Accumulator_array_length_ptr,
    Accumulator_array_offset_ptr,
    Accumulator_array_offset,
    Accumulator_conduitKey_ptr,
    Accumulator_itemSizeOffsetDifference,
    Accumulator_selector_ptr,
    AccumulatorArmed,
    AccumulatorDisarmed,
    Conduit_transferItem_amount_ptr,
    Conduit_transferItem_from_ptr,
    Conduit_transferItem_identifier_ptr,
    Conduit_transferItem_size,
    Conduit_transferItem_to_ptr,
    Conduit_transferItem_token_ptr,
    FreeMemoryPointerSlot,
    OneWord,
    TwoWords
} from "seaport-types/src/lib/ConsiderationConstants.sol";

import {
    Error_selector_offset,
    NativeTokenTransferGenericFailure_error_account_ptr,
    NativeTokenTransferGenericFailure_error_amount_ptr,
    NativeTokenTransferGenericFailure_error_length,
    NativeTokenTransferGenericFailure_error_selector
} from "seaport-types/src/lib/ConsiderationErrorConstants.sol";

import {
    _revertInvalidCallToConduit,
    _revertInvalidConduit,
    _revertInvalidERC721TransferAmount,
    _revertUnusedItemParameters
} from "seaport-types/src/lib/ConsiderationErrors.sol";

/**
 * @title Executor
 * @author 0age
 * @notice Executor contains functions related to processing executions (i.e.
 *         transferring items, either directly or via conduits).
 */
contract Executor is Verifiers, TokenTransferrer {
    /**
     * @dev Derive and set hashes, reference chainId, and associated domain
     *      separator during deployment.
     *
     * @param conduitController A contract that deploys conduits, or proxies
     *                          that may optionally be used to transfer approved
     *                          ERC20/721/1155 tokens.
     */
    constructor(address conduitController) Verifiers(conduitController) {}

    /**
     * @dev Internal function to transfer a given item.
     *
     * @param item                  The item to transfer including an amount
     *                              and recipient.
     * @param offerer               The account offering the item, i.e. the
     *                              from address.
     * @param conduitKey            A bytes32 value indicating what
     *                              corresponding conduit, if any, to source
     *                              token approvals from. The zero hash
     *                              signifies that no conduit should be used
     *                              (and direct approvals set on Consideration)
     * @param accumulatorStruct     A struct containing conduit transfer data
     *                              and its corresponding conduitKey.
     */
    function _transfer(
        ReceivedItem memory item,
        address offerer,
        bytes32 conduitKey,
        AccumulatorStruct memory accumulatorStruct
    ) internal {
        // If the item type indicates Ether or a native token...
        if (item.itemType == ItemType.NATIVE) {
            // Ensure neither the token nor the identifier parameters are set.
            if ((uint160(item.token) | item.identifier) != 0) {
                revert UnusedItemParameters();
            }

            // Transfer the native tokens to the recipient.
            _transferNativeTokens(item.recipient, item.amount);
        } else if (item.itemType == ItemType.ERC20) {
            // Ensure that no identifier is supplied.
            if (item.identifier != 0) {
                revert UnusedItemParameters();
            }

            // Transfer ERC20 tokens from the offerer to the recipient.
            _transferERC20(
                item.token,
                offerer,
                item.recipient,
                item.amount,
                conduitKey,
                accumulatorStruct
            );
        } else if (item.itemType == ItemType.ERC721) {
            // Transfer ERC721 token from the offerer to the recipient.
            _transferERC721(
                item.token,
                offerer,
                item.recipient,
                item.identifier,
                item.amount,
                conduitKey,
                accumulatorStruct
            );
        } else {
            // Transfer ERC1155 token from the offerer to the recipient.
            _transferERC1155(
                item.token,
                offerer,
                item.recipient,
                item.identifier,
                item.amount,
                conduitKey,
                accumulatorStruct
            );
        }
    }

    /**
     * @dev Internal function to transfer Ether or other native tokens to a
     *      given recipient.
     *
     * @param to     The recipient of the transfer.
     * @param amount The amount to transfer.
     */
    function _transferNativeTokens(address payable to, uint256 amount) internal {
        // Ensure that the supplied amount is non-zero.
        _assertNonZeroAmount(amount);

        // Declare a variable indicating whether the call was successful or not.
        bool success;

        assembly {
            // Transfer the native token and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        // If the call fails...
        if (!success) {
            // Revert and pass the revert reason along if one was returned.
            _revertWithReasonIfOneIsReturned();

            // Otherwise, revert with a generic error message.
            assembly {
                // Store left-padded selector with push4, mem[28:32] = selector
                mstore(0, NativeTokenTransferGenericFailure_error_selector)

                // Write `to` and `amount` arguments.
                mstore(NativeTokenTransferGenericFailure_error_account_ptr, to)
                mstore(NativeTokenTransferGenericFailure_error_amount_ptr, amount)

                // revert(abi.encodeWithSignature(
                //     "NativeTokenTransferGenericFailure(address,uint256)",
                //     to,
                //     amount
                // ))
                revert(Error_selector_offset, NativeTokenTransferGenericFailure_error_length)
            }
        }
    }

    /**
     * @dev Internal function to transfer ERC20 tokens from a given originator
     *      to a given recipient using a given conduit if applicable. Sufficient
     *      approvals must be set on this contract, the conduit.
     *
     * @param token                 The ERC20 token to transfer.
     * @param from                  The originator of the transfer.
     * @param to                    The recipient of the transfer.
     * @param amount                The amount to transfer.
     * @param conduitKey            A bytes32 value indicating what
     *                              corresponding conduit, if any, to source
     *                              token approvals from. The zero hash
     *                              signifies that no conduit should be used
     *                              (and direct approvals set on Consideration)
     * @param accumulatorStruct     A struct containing conduit transfer data
     *                              and its corresponding conduitKey.
     */
    function _transferERC20(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes32 conduitKey,
        AccumulatorStruct memory accumulatorStruct
    ) internal {
        // Ensure that the supplied amount is non-zero.
        _assertNonZeroAmount(amount);

        // Trigger accumulated transfers if the conduits differ.
        _triggerIfArmedAndNotAccumulatable(accumulatorStruct, conduitKey);

        // If no conduit has been specified...
        if (conduitKey == bytes32(0)) {
            // Perform the token transfer directly.
            _performERC20Transfer(token, from, to, amount);
        } else {
            // Insert the call to the conduit into the accumulator.
            _insert(
                conduitKey,
                accumulatorStruct,
                ConduitItemType.ERC20,
                token,
                from,
                to,
                uint256(0),
                amount
            );
        }
    }

    /**
     * @dev Internal function to transfer a single ERC721 token from a given
     *      originator to a given recipient. Sufficient approvals must be set,
     *      either on the respective conduit or on this contract itself.
     *
     * @param token                 The ERC721 token to transfer.
     * @param from                  The originator of the transfer.
     * @param to                    The recipient of the transfer.
     * @param identifier            The tokenId to transfer.
     * @param amount                The "amount" (this value must be equal
     *                              to one).
     * @param conduitKey            A bytes32 value indicating what
     *                              corresponding conduit, if any, to source
     *                              token approvals from. The zero hash
     *                              signifies that no conduit should be used
     *                              (and direct approvals set on Consideration)
     * @param accumulatorStruct     A struct containing conduit transfer data
     *                              and its corresponding conduitKey.
     */
    function _transferERC721(
        address token,
        address from,
        address to,
        uint256 identifier,
        uint256 amount,
        bytes32 conduitKey,
        AccumulatorStruct memory accumulatorStruct
    ) internal {
        // Trigger accumulated transfers if the conduits differ.
        _triggerIfArmedAndNotAccumulatable(accumulatorStruct, conduitKey);

        // If no conduit has been specified...
        if (conduitKey == bytes32(0)) {
            // Ensure that exactly one 721 item is being transferred.
            if (amount != 1) {
                revert InvalidERC721TransferAmount(amount);
            }

            // Perform transfer via the token contract directly.
            _performERC721Transfer(token, from, to, identifier);
        } else {
            // Insert the call to the conduit into the accumulator.
            _insert(
                conduitKey,
                accumulatorStruct,
                ConduitItemType.ERC721,
                token,
                from,
                to,
                identifier,
                amount
            );
        }
    }

    /**
     * @dev Internal function to transfer ERC1155 tokens from a given originator
     *      to a given recipient. Sufficient approvals must be set, either on
     *      the respective conduit or on this contract itself.
     *
     * @param token                 The ERC1155 token to transfer.
     * @param from                  The originator of the transfer.
     * @param to                    The recipient of the transfer.
     * @param identifier            The tokenId to transfer.
     * @param amount                The amount to transfer.
     * @param conduitKey            A bytes32 value indicating what
     *                              corresponding conduit, if any, to source
     *                              token approvals from. The zero hash
     *                              signifies that no conduit should be used
     *                              (and direct approvals set on Consideration)
     * @param accumulatorStruct     A struct containing conduit transfer data
     *                              and its corresponding conduitKey.
     */
    function _transferERC1155(
        address token,
        address from,
        address to,
        uint256 identifier,
        uint256 amount,
        bytes32 conduitKey,
        AccumulatorStruct memory accumulatorStruct
    ) internal {
        // Ensure that the supplied amount is non-zero.
        _assertNonZeroAmount(amount);

        // Trigger accumulated transfers if the conduits differ.
        _triggerIfArmedAndNotAccumulatable(accumulatorStruct, conduitKey);

        // If no conduit has been specified...
        if (conduitKey == bytes32(0)) {
            // Perform transfer via the token contract directly.
            _performERC1155Transfer(token, from, to, identifier, amount);
        } else {
            // Insert the call to the conduit into the accumulator.
            _insert(
                conduitKey,
                accumulatorStruct,
                ConduitItemType.ERC1155,
                token,
                from,
                to,
                identifier,
                amount
            );
        }
    }

    /**
     * @dev Internal function to trigger a call to the conduit currently held by
     *      the accumulator if the accumulator contains item transfers (i.e. it
     *      is "armed") and the supplied conduit key does not match the key held
     *      by the accumulator.
     *
     * @param accumulatorStruct A struct containing conduit transfer data
     *                          and its corresponding conduitKey.
     * @param conduitKey        A bytes32 value indicating what corresponding
     *                          conduit, if any, to source token approvals
     *                          from. The zero hash signifies that no conduit
     *                          should be used (and direct approvals set on
     *                          Consideration)
     */
    function _triggerIfArmedAndNotAccumulatable(
        AccumulatorStruct memory accumulatorStruct,
        bytes32 conduitKey
    ) internal {
        // Perform conduit call if the set key does not match the supplied key.
        if (accumulatorStruct.conduitKey != conduitKey) {
            _triggerIfArmed(accumulatorStruct);
        }
    }

    /**
     * @dev Internal function to trigger a call to the conduit currently held by
     *      the accumulator if the accumulator contains item transfers (i.e. it
     *      is "armed").
     *
     * @param accumulatorStruct A struct containing conduit transfer data
     *                          and its corresponding conduitKey.
     */
    function _triggerIfArmed(
        AccumulatorStruct memory accumulatorStruct
    ) internal {
        // Exit if the accumulator is not "armed".
        if (accumulatorStruct.transfers.length == 0) {
            return;
        }

        // Perform conduit call.
        _trigger(accumulatorStruct);
    }

    /**
     * @dev Internal function to trigger a call to the conduit corresponding to
     *      a given conduit key, supplying all accumulated item transfers. The
     *      accumulator will be "disarmed" and reset in the process.
     *
     * @param accumulatorStruct A struct containing conduit transfer data
     *                          and its corresponding conduitKey.
     */
    function _trigger(AccumulatorStruct memory accumulatorStruct) internal {
        // Call the conduit with all the accumulated transfers.
        ConduitInterface(_getConduit(accumulatorStruct.conduitKey)).execute(
            accumulatorStruct.transfers
        );

        // Reset accumulator length to signal that it is now "disarmed".
        delete accumulatorStruct.transfers;
    }

    /**
     * @dev Internal function to perform a call to the conduit corresponding to
     *      a given conduit key based on the offset and size of the calldata in
     *      question in memory.
     *
     * @param conduitKey     A bytes32 value indicating what corresponding
     *                       conduit, if any, to source token approvals from.
     *                       The zero hash signifies that no conduit should be
     *                       used, with direct approvals set on this contract.
     * @param callDataOffset The memory pointer where calldata is contained.
     * @param callDataSize   The size of calldata in memory.
     */
    function _callConduitUsingOffsets(bytes32 conduitKey, uint256 callDataOffset, uint256 callDataSize) internal {
        // Derive the address of the conduit using the conduit key.
        address conduit = _deriveConduit(conduitKey);

        bool success;
        bytes4 result;

        // call the conduit.
        assembly {
            // Ensure first word of scratch space is empty.
            mstore(0, 0)

            // Perform call, placing first word of return data in scratch space.
            success := call(gas(), conduit, 0, callDataOffset, callDataSize, 0, OneWord)

            // Take value from scratch space and place it on the stack.
            result := mload(0)
        }

        // If the call failed...
        if (!success) {
            // Pass along whatever revert reason was given by the conduit.
            _revertWithReasonIfOneIsReturned();

            // Otherwise, revert with a generic error.
            _revertInvalidCallToConduit(conduit);
        }

        // Ensure result was extracted and matches EIP-1271 magic value.
        if (result != ConduitInterface.execute.selector) {
            _revertInvalidConduit(conduitKey, conduit);
        }
    }

    /**
     * @dev Internal function get the conduit derived by the provided
     *      conduit key.
     *
     * @param conduitKey A bytes32 value indicating what corresponding conduit,
     *                   if any, to source token approvals from. This value is
     *                   the "salt" parameter supplied by the deployer (i.e. the
     *                   conduit controller) when deploying the given conduit.
     *
     * @return conduit   The address of the conduit associated with the given
     *                   conduit key.
     */
    function _getConduit(
        bytes32 conduitKey
    ) internal view returns (address conduit) {
        // Derive the address of the conduit using the conduit key.
        conduit = _deriveConduit(conduitKey);

        // If the conduit does not have runtime code (i.e. is not deployed)...
        if (conduit.code.length == 0) {
            // Revert with an error indicating an invalid conduit.
            revert InvalidConduit(conduitKey, conduit);
        }
    }

    /**
     * @dev Internal pure function to place an item transfer into an accumulator
     *      that collects a series of transfers to execute against a given
     *      conduit in a single call.
     *
     * @param conduitKey        A bytes32 value indicating what
     *                          corresponding conduit, if any, to source
     *                          token approvals from. The zero hash
     *                          signifies that no conduit should be used
     *                          (and direct approvals set on Consideration)
     * @param accumulatorStruct A struct containing conduit transfer data
     *                          and its corresponding conduitKey.
     * @param itemType          The type of the item to transfer.
     * @param token             The token to transfer.
     * @param from              The originator of the transfer.
     * @param to                The recipient of the transfer.
     * @param identifier        The tokenId to transfer.
     * @param amount            The amount to transfer.
     */
    function _insert(
        bytes32 conduitKey,
        AccumulatorStruct memory accumulatorStruct,
        ConduitItemType itemType,
        address token,
        address from,
        address to,
        uint256 identifier,
        uint256 amount
    ) internal pure {
        /**
         *   The following is highly inefficient, but written this way to
         *   simply demonstrate what is performed by the optimized contract.
         */

        // Get the current length of the accumulator's transfers.
        uint256 currentTransferLength = accumulatorStruct.transfers.length;

        // Create a new array to "insert" the new transfer.
        ConduitTransfer[] memory newTransfers = (
            new ConduitTransfer[](currentTransferLength + 1)
        );

        // Fill new array with old transfers.
        for (uint256 i = 0; i < currentTransferLength; ++i) {
            // Get the old transfer.
            ConduitTransfer memory oldTransfer = accumulatorStruct.transfers[i];

            // Add the old transfer into the new array.
            newTransfers[i] = ConduitTransfer(
                oldTransfer.itemType,
                oldTransfer.token,
                oldTransfer.from,
                oldTransfer.to,
                oldTransfer.identifier,
                oldTransfer.amount
            );
        }

        // Insert new transfer into array.
        newTransfers[currentTransferLength] = ConduitTransfer(
            itemType,
            token,
            from,
            to,
            identifier,
            amount
        );

        // Set accumulator struct transfers to new transfers.
        accumulatorStruct.transfers = newTransfers;

        // Set the conduitkey of the current transfers.
        accumulatorStruct.conduitKey = conduitKey;
    }
}
