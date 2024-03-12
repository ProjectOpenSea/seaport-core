// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    ItemType,
    OrderType,
    Side
} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {
    AdvancedOrder,
    ConsiderationItem,
    CriteriaResolver,
    MemoryPointer,
    OfferItem,
    OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {
    _revertCriteriaNotEnabledForItem,
    _revertInvalidProof,
    _revertOrderCriteriaResolverOutOfRange
} from "seaport-types/src/lib/ConsiderationErrors.sol";

import {
    CriteriaResolutionErrors
} from "seaport-types/src/interfaces/CriteriaResolutionErrors.sol";

import {
    OneWord,
    OneWordShift,
    OrderParameters_consideration_head_offset,
    Selector_length,
    TwoWords
} from "seaport-types/src/lib/ConsiderationConstants.sol";

import {
    ConsiderationCriteriaResolverOutOfRange_err_selector,
    Error_selector_offset,
    OfferCriteriaResolverOutOfRange_error_selector,
    UnresolvedConsiderationCriteria_error_itemIndex_ptr,
    UnresolvedConsiderationCriteria_error_length,
    UnresolvedConsiderationCriteria_error_orderIndex_ptr,
    UnresolvedConsiderationCriteria_error_selector,
    UnresolvedOfferCriteria_error_selector
} from "seaport-types/src/lib/ConsiderationErrorConstants.sol";

/**
 * @title CriteriaResolution
 * @author 0age
 * @notice CriteriaResolution contains a collection of pure functions related to
 *         resolving criteria-based items.
 */
contract CriteriaResolution is CriteriaResolutionErrors {
    /**
     * @dev Internal pure function to apply criteria resolvers containing
     *      specific token identifiers and associated proofs to order items.
     *
     * @param advancedOrders     The orders to apply criteria resolvers to.
     * @param criteriaResolvers  An array where each element contains a
     *                           reference to a specific order as well as that
     *                           order's offer or consideration, a token
     *                           identifier, and a proof that the supplied token
     *                           identifier is contained in the order's merkle
     *                           root. Note that a root of zero indicates that
     *                           any transferable token identifier is valid and
     *                           that no proof needs to be supplied.
     */
    function _applyCriteriaResolvers(
        AdvancedOrder[] memory advancedOrders,
        CriteriaResolver[] memory criteriaResolvers
    ) internal pure {
        // Skip overflow checks as all for loops are indexed starting at zero.
        unchecked {
            // Retrieve length of criteria resolvers array and place on stack.
            uint256 totalCriteriaResolvers = criteriaResolvers.length;

            // Retrieve length of orders array and place on stack.
            uint256 totalAdvancedOrders = advancedOrders.length;

            // Iterate over each criteria resolver.
            for (uint256 i = 0; i < totalCriteriaResolvers; ++i) {
                // Retrieve the criteria resolver.
                CriteriaResolver memory criteriaResolver = (
                    criteriaResolvers[i]
                );

                // Read the order index from memory and place it on the stack.
                uint256 orderIndex = criteriaResolver.orderIndex;

                // Ensure that the order index is in range.
                if (orderIndex >= totalAdvancedOrders) {
                    _revertOrderCriteriaResolverOutOfRange(
                        criteriaResolver.side
                    );
                }

                // Retrieve the referenced advanced order.
                AdvancedOrder memory advancedOrder = advancedOrders[orderIndex];

                // Skip criteria resolution for order if not fulfilled.
                if (advancedOrder.numerator == 0) {
                    continue;
                }

                // Retrieve the parameters for the order.
                OrderParameters memory orderParameters = (
                    advancedOrder.parameters
                );

                {
                    // Get a pointer to the list of items to give to
                    // _updateCriteriaItem. If the resolver refers to a
                    // consideration item, this array pointer will be replaced
                    // with the consideration array.
                    OfferItem[] memory items = orderParameters.offer;

                    // Read component index from memory and place it on stack.
                    uint256 componentIndex = criteriaResolver.index;

                    // Get error selector for `OfferCriteriaResolverOutOfRange`.
                    uint256 errorSelector = (
                        OfferCriteriaResolverOutOfRange_error_selector
                    );

                    // If the resolver refers to a consideration item...
                    if (criteriaResolver.side != Side.OFFER) {
                        // Get the pointer to `orderParameters.consideration`
                        // Using the array directly has a significant impact on
                        // the optimized compiler output.
                        MemoryPointer considerationPtr = orderParameters
                            .toMemoryPointer()
                            .pptrOffset(
                                OrderParameters_consideration_head_offset
                            );

                        // Replace the items pointer with a pointer to the
                        // consideration array.
                        assembly {
                            items := considerationPtr
                        }

                        // Replace the error selector with the selector for
                        // `ConsiderationCriteriaResolverOutOfRange`.
                        errorSelector = (
                            ConsiderationCriteriaResolverOutOfRange_err_selector
                        );
                    }

                    // Ensure that the component index is in range.
                    if (componentIndex >= items.length) {
                        assembly {
                            // Revert with either
                            // `OfferCriteriaResolverOutOfRange()` or
                            // `ConsiderationCriteriaResolverOutOfRange()`,
                            // depending on whether the resolver refers to a
                            // consideration item.
                            mstore(0, errorSelector)
                            // revert(abi.encodeWithSignature(
                            //    "OfferCriteriaResolverOutOfRange()"
                            // ))
                            // or
                            // revert(abi.encodeWithSignature(
                            //    "ConsiderationCriteriaResolverOutOfRange()"
                            // ))
                            revert(Error_selector_offset, Selector_length)
                        }
                    }

                    // Apply the criteria resolver to the item in question.
                    _updateCriteriaItem(
                        items,
                        componentIndex,
                        criteriaResolver
                    );
                }
            }

            // Iterate over each advanced order.
            for (uint256 i = 0; i < totalAdvancedOrders; ++i) {
                // Retrieve the advanced order.
                AdvancedOrder memory advancedOrder = advancedOrders[i];

                // Skip criteria resolution for order if not fulfilled.
                if (advancedOrder.numerator == 0) {
                    continue;
                }

                // Retrieve the parameters for the order.
                OrderParameters memory orderParameters = (
                    advancedOrder.parameters
                );

                OrderType orderType = orderParameters.orderType;

                _ensureAllRequiredCriteriaResolved(
                    i,
                    orderParameters.consideration,
                    orderType,
                    UnresolvedConsiderationCriteria_error_selector
                );

                _toOfferItemArgumentType(_ensureAllRequiredCriteriaResolved)(
                    i,
                    orderParameters.offer,
                    orderType,
                    UnresolvedOfferCriteria_error_selector
                );
            }
        }
    }

    /**
     * @dev Internal pure function to examine an array of items and ensure that
     *      all criteria-based items (with the exception of wildcard items on
     *      contract orders) have had a criteria resolver successfully applied.
     *
     * @param orderIndex     The index of the order being examined.
     * @param items          The items to examine. These are consideration items
     *                       in the default case, but offer items are also
     *                       casted to consideration items as required.
     * @param orderType      The type of order being examined.
     * @param revertSelector The selector to use when reverting.
     */
    function _ensureAllRequiredCriteriaResolved(
        uint256 orderIndex,
        ConsiderationItem[] memory items,
        OrderType orderType,
        uint256 revertSelector
    ) internal pure {
        // Read items array length from memory and place on stack.
        uint256 totalItems = items.length;

        // Iterate over each item on the order.
        for (uint256 i = 0; i < totalItems; ++i) {
            ConsiderationItem memory item = items[i];

            // Revert if the item is still a criteria item unless the
            // order is a contract order and the identifier is 0.
            ItemType itemType = item.itemType;
            uint256 identifierOrCriteria = item.identifierOrCriteria;

            assembly {
                if and(
                    gt(itemType, 3), // Criteria-based item
                    or(
                        iszero(eq(orderType, 4)), // not OrderType.CONTRACT
                        iszero(iszero(identifierOrCriteria)) // not wildcard
                    )
                ) {
                    // Store left-padded selector with push4 (reduces bytecode),
                    // mem[28:32] = selector
                    mstore(0, revertSelector)

                    // Store arguments.
                    mstore(
                        UnresolvedConsiderationCriteria_error_orderIndex_ptr,
                        orderIndex
                    )
                    mstore(
                        UnresolvedConsiderationCriteria_error_itemIndex_ptr,
                        i
                    )

                    // Revert with appropriate UnresolvedCriteria error message.
                    // Unresolved[Offer|Consideration]Criteria(uint256, uint256)
                    revert(
                        Error_selector_offset,
                        UnresolvedConsiderationCriteria_error_length
                    )
                }
            }
        }
    }

    /**
     * @dev Internal pure function to perform a function cast from a function
     *      that accepts consideration items to a function that accepts offer
     *      items, used by _ensureAllRequiredCriteriaResolved to ensure that
     *      all necessary criteria items have been resolved for an order.
     *
     * @param inFn  The function that accepts consideration items.
     * @param outFn The function that accepts offer items.
     */
    function _toOfferItemArgumentType(
        function(uint256, ConsiderationItem[] memory, OrderType, uint256)
            internal
            pure inFn
    )
        internal
        pure
        returns (
            function(uint256, OfferItem[] memory, OrderType, uint256)
                internal
                pure outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Internal pure function to update a criteria item.
     *
     * @param offer             The offer containing the item to update.
     * @param componentIndex    The index of the item to update.
     * @param criteriaResolver  The criteria resolver to use to update the item.
     */
    function _updateCriteriaItem(
        OfferItem[] memory offer,
        uint256 componentIndex,
        CriteriaResolver memory criteriaResolver
    ) internal pure {
        // Retrieve relevant item using the component index.
        OfferItem memory offerItem = offer[componentIndex];

        // Read item type and criteria from memory & place on stack.
        ItemType itemType = offerItem.itemType;

        // Ensure the specified item type indicates criteria usage.
        if (!_isItemWithCriteria(itemType)) {
            _revertCriteriaNotEnabledForItem();
        }

        uint256 identifierOrCriteria = offerItem.identifierOrCriteria;

        // If criteria is not 0 (i.e. a collection-wide criteria-based item)...
        if (identifierOrCriteria != uint256(0)) {
            // Verify identifier inclusion in criteria root using proof.
            _verifyProof(
                criteriaResolver.identifier,
                identifierOrCriteria,
                criteriaResolver.criteriaProof
            );
        } else if (criteriaResolver.criteriaProof.length != 0) {
            // Revert if non-empty proof is supplied for a collection-wide item.
            _revertInvalidProof();
        }

        // Update item type to remove criteria usage.
        // Use assembly to operate on ItemType enum as a number.
        ItemType newItemType;
        assembly {
            // Item type 4 becomes 2 and item type 5 becomes 3.
            newItemType := sub(itemType, 2)
        }
        offerItem.itemType = newItemType;

        // Update identifier w/ supplied identifier.
        offerItem.identifierOrCriteria = criteriaResolver.identifier;
    }

    /**
     * @dev Internal pure function to check whether a given item type represents
     *      a criteria-based ERC721 or ERC1155 item (e.g. an item that can be
     *      resolved to one of a number of different identifiers at the time of
     *      order fulfillment).
     *
     * @param itemType The item type in question.
     *
     * @return withCriteria A boolean indicating that the item type in question
     *                      represents a criteria-based item.
     */
    function _isItemWithCriteria(
        ItemType itemType
    ) internal pure returns (bool withCriteria) {
        // ERC721WithCriteria is ItemType 4. ERC1155WithCriteria is ItemType 5.
        assembly {
            withCriteria := gt(itemType, 3)
        }
    }

    /**
     * @dev Internal pure function to ensure that a given element is contained
     *      in a merkle root via a supplied proof.
     *
     * @param leaf  The element for which to prove inclusion.
     * @param root  The merkle root that inclusion will be proved against.
     * @param proof The merkle proof.
     */
    function _verifyProof(
        uint256 leaf,
        uint256 root,
        bytes32[] memory proof
    ) internal pure {
        // Declare a variable that will be used to determine proof validity.
        bool isValid;

        // Utilize assembly to efficiently verify the proof against the root.
        assembly {
            // Store the leaf at the beginning of scratch space.
            mstore(0, leaf)

            // Derive the hash of the leaf to use as the initial proof element.
            let computedHash := keccak256(0, OneWord)

            // Get memory start location of the first element in proof array.
            let data := add(proof, OneWord)

            // Iterate over each proof element to compute the root hash.
            for {
                // Left shift by 5 is equivalent to multiplying by 0x20.
                let end := add(data, shl(OneWordShift, mload(proof)))
            } lt(data, end) {
                // Increment by one word at a time.
                data := add(data, OneWord)
            } {
                // Get the proof element.
                let loadedData := mload(data)

                // Sort proof elements and place them in scratch space.
                // Slot of `computedHash` in scratch space.
                // If the condition is true: 0x20, otherwise: 0x00.
                let scratch := shl(OneWordShift, gt(computedHash, loadedData))

                // Store elements to hash contiguously in scratch space. Scratch
                // space is 64 bytes (0x00 - 0x3f) & both elements are 32 bytes.
                mstore(scratch, computedHash)
                mstore(xor(scratch, OneWord), loadedData)

                // Derive the updated hash.
                computedHash := keccak256(0, TwoWords)
            }

            // Compare the final hash to the supplied root.
            isValid := eq(computedHash, root)
        }

        // Revert if computed hash does not equal supplied root.
        if (!isValid) {
            _revertInvalidProof();
        }
    }
}
