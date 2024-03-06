// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    AdvancedOrder,
    ConsiderationItem,
    CriteriaResolver,
    Fulfillment,
    FulfillmentComponent,
    OfferItem,
    Order,
    OrderParameters,
    ReceivedItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {
    AdvancedOrder_denominator_offset,
    AdvancedOrder_extraData_offset,
    AdvancedOrder_fixed_segment_0,
    AdvancedOrder_head_size,
    AdvancedOrder_numerator_offset,
    AdvancedOrder_signature_offset,
    AdvancedOrderPlusOrderParameters_head_size,
    Common_amount_offset,
    Common_endAmount_offset,
    Common_identifier_offset,
    Common_token_offset,
    ConsiderationItem_recipient_offset,
    ConsiderationItem_size_with_head_pointer,
    ConsiderationItem_size,
    CriteriaResolver_criteriaProof_offset,
    CriteriaResolver_fixed_segment_0,
    CriteriaResolver_head_size,
    ThreeWords,
    FreeMemoryPointerSlot,
    Fulfillment_considerationComponents_offset,
    Fulfillment_head_size,
    FulfillmentComponent_mem_tail_size_shift,
    FulfillmentComponent_mem_tail_size,
    generateOrder_maximum_returned_array_length,
    OfferItem_size_with_head_pointer,
    OfferItem_size,
    OneWord,
    OneWordShift,
    OnlyFullWordMask,
    Order_head_size,
    Order_signature_offset,
    OrderComponents_OrderParameters_common_head_size,
    OrderParameters_consideration_head_offset,
    OrderParameters_head_size,
    OrderParameters_offer_head_offset,
    OrderParameters_totalOriginalConsiderationItems_offset,
    ReceivedItem_recipient_offset,
    ReceivedItem_size,
    ReceivedItem_size_excluding_recipient,
    SpentItem_size_shift,
    SpentItem_size,
    ThirtyOneBytes,
    TwoWords
} from "seaport-types/src/lib/ConsiderationConstants.sol";

import {
    CalldataPointer,
    malloc,
    MemoryPointer,
    OffsetOrLengthMask
} from "seaport-types/src/helpers/PointerLibraries.sol";

contract ConsiderationDecoder {
    /**
     * @dev Takes a bytes array from calldata and copies it into memory.
     *
     * @param cdPtrLength A calldata pointer to the start of the bytes array in
     *                    calldata which contains the length of the array.
     *
     * @return mPtrLength A memory pointer to the start of the bytes array in
     *                    memory which contains the length of the array.
     */
    function _decodeBytes(CalldataPointer cdPtrLength)
        internal
        pure
        returns (MemoryPointer mPtrLength)
    {
        assembly {
            // Get the current free memory pointer.
            mPtrLength := mload(FreeMemoryPointerSlot)

            // Derive the size of the bytes array, rounding up to nearest word
            // and adding a word for the length field. Note: masking
            // `calldataload(cdPtrLength)` is redundant here.
            let size :=
                add(
                    and(
                        add(calldataload(cdPtrLength), ThirtyOneBytes),
                        OnlyFullWordMask
                    ),
                    OneWord
                )

            // Copy bytes from calldata into memory based on pointers and size.
            calldatacopy(mPtrLength, cdPtrLength, size)

            // Store the masked value in memory. Note: the value of `size` is at
            // least 32, meaning the calldatacopy above will at least write to
            // `[mPtrLength, mPtrLength + 32)`.
            mstore(
                mPtrLength, and(calldataload(cdPtrLength), OffsetOrLengthMask)
            )

            // Update free memory pointer based on the size of the bytes array.
            mstore(FreeMemoryPointerSlot, add(mPtrLength, size))
        }
    }

    /**
     * @dev Takes an offer array from calldata and copies it into memory.
     *
     * @param cdPtrLength A calldata pointer to the start of the offer array
     *                    in calldata which contains the length of the array.
     *
     * @return mPtrLength A memory pointer to the start of the offer array in
     *                    memory which contains the length of the array.
     */
    function _decodeOffer(CalldataPointer cdPtrLength)
        internal
        pure
        returns (MemoryPointer mPtrLength)
    {
        assembly {
            // Retrieve length of array, masking to prevent potential overflow.
            let arrLength := and(calldataload(cdPtrLength), OffsetOrLengthMask)

            // Get the current free memory pointer.
            mPtrLength := mload(FreeMemoryPointerSlot)

            // Write the array length to memory.
            mstore(mPtrLength, arrLength)

            // Derive the head by adding one word to the length pointer.
            let mPtrHead := add(mPtrLength, OneWord)

            // Derive the tail by adding one word per element (note that structs
            // are written to memory with an offset per struct element).
            let mPtrTail := add(mPtrHead, shl(OneWordShift, arrLength))

            // Track the next tail, beginning with the initial tail value.
            let mPtrTailNext := mPtrTail

            // Copy all offer array data into memory at the tail pointer.
            calldatacopy(
                mPtrTail,
                add(cdPtrLength, OneWord),
                mul(arrLength, OfferItem_size)
            )

            // Track the next head pointer, starting with initial head value.
            let mPtrHeadNext := mPtrHead

            // Iterate over each head pointer until it reaches the tail.
            for { } lt(mPtrHeadNext, mPtrTail) { } {
                // Write the next tail pointer to next head pointer in memory.
                mstore(mPtrHeadNext, mPtrTailNext)

                // Increment the next head pointer by one word.
                mPtrHeadNext := add(mPtrHeadNext, OneWord)

                // Increment the next tail pointer by the size of an offer item.
                mPtrTailNext := add(mPtrTailNext, OfferItem_size)
            }

            // Update free memory pointer to allocate memory up to end of tail.
            mstore(FreeMemoryPointerSlot, mPtrTailNext)
        }
    }

    /**
     * @dev Takes a consideration array from calldata and copies it into memory.
     *
     * @param cdPtrLength A calldata pointer to the start of the consideration
     *                    array in calldata which contains the length of the
     *                    array.
     *
     * @return mPtrLength A memory pointer to the start of the consideration
     *                    array in memory which contains the length of the
     *                    array.
     */
    function _decodeConsideration(CalldataPointer cdPtrLength)
        internal
        pure
        returns (MemoryPointer mPtrLength)
    {
        assembly {
            // Retrieve length of array, masking to prevent potential overflow.
            let arrLength := and(calldataload(cdPtrLength), OffsetOrLengthMask)

            // Get the current free memory pointer.
            mPtrLength := mload(FreeMemoryPointerSlot)

            // Write the array length to memory.
            mstore(mPtrLength, arrLength)

            // Derive the head by adding one word to the length pointer.
            let mPtrHead := add(mPtrLength, OneWord)

            // Derive the tail by adding one word per element (note that structs
            // are written to memory with an offset per struct element).
            let mPtrTail := add(mPtrHead, shl(OneWordShift, arrLength))

            // Track the next tail, beginning with the initial tail value.
            let mPtrTailNext := mPtrTail

            // Copy all consideration array data into memory at tail pointer.
            calldatacopy(
                mPtrTail,
                add(cdPtrLength, OneWord),
                mul(arrLength, ConsiderationItem_size)
            )

            // Track the next head pointer, starting with initial head value.
            let mPtrHeadNext := mPtrHead

            // Iterate over each head pointer until it reaches the tail.
            for { } lt(mPtrHeadNext, mPtrTail) { } {
                // Write the next tail pointer to next head pointer in memory.
                mstore(mPtrHeadNext, mPtrTailNext)

                // Increment the next head pointer by one word.
                mPtrHeadNext := add(mPtrHeadNext, OneWord)

                // Increment next tail pointer by size of a consideration item.
                mPtrTailNext := add(mPtrTailNext, ConsiderationItem_size)
            }

            // Update free memory pointer to allocate memory up to end of tail.
            mstore(FreeMemoryPointerSlot, mPtrTailNext)
        }
    }

    /**
     * @dev Takes a calldata pointer and memory pointer and copies a referenced
     *      OrderParameters struct and associated offer and consideration data
     *      to memory.
     *
     * @param cdPtr A calldata pointer for the OrderParameters struct.
     * @param mPtr A memory pointer to the OrderParameters struct head.
     */
    function _decodeOrderParametersTo(CalldataPointer cdPtr, MemoryPointer mPtr)
        internal
        pure
    {
        // Copy the full OrderParameters head from calldata to memory.
        cdPtr.copy(mPtr, OrderParameters_head_size);

        // Resolve the offer calldata offset, use that to decode and copy offer
        // from calldata, and write resultant memory offset to head in memory.
        mPtr.offset(OrderParameters_offer_head_offset).write(
            _decodeOffer(cdPtr.pptrOffset(OrderParameters_offer_head_offset))
        );

        // Resolve consideration calldata offset, use that to copy consideration
        // from calldata, and write resultant memory offset to head in memory.
        mPtr.offset(OrderParameters_consideration_head_offset).write(
            _decodeConsideration(
                cdPtr.pptrOffset(OrderParameters_consideration_head_offset)
            )
        );
    }

    /**
     * @dev Takes a calldata pointer to an OrderParameters struct and copies the
     *      decoded struct to memory.
     *
     * @param cdPtr A calldata pointer for the OrderParameters struct.
     *
     * @return mPtr A memory pointer to the OrderParameters struct head.
     */
    function _decodeOrderParameters(CalldataPointer cdPtr)
        internal
        pure
        returns (MemoryPointer mPtr)
    {
        // Allocate required memory for the OrderParameters head (offer and
        // consideration are allocated independently).
        mPtr = malloc(OrderParameters_head_size);

        // Decode and copy the order parameters to the newly allocated memory.
        _decodeOrderParametersTo(cdPtr, mPtr);
    }

    /**
     * @dev Takes a calldata pointer to an Order struct and copies the decoded
     *      struct to memory.
     *
     * @param cdPtr A calldata pointer for the Order struct.
     *
     * @return mPtr A memory pointer to the Order struct head.
     */
    function _decodeOrder(CalldataPointer cdPtr)
        internal
        pure
        returns (MemoryPointer mPtr)
    {
        // Allocate required memory for the Order head (OrderParameters and
        // signature are allocated independently).
        mPtr = malloc(Order_head_size);

        // Resolve OrderParameters calldata offset, use it to decode and copy
        // from calldata, and write resultant memory offset to head in memory.
        mPtr.write(_decodeOrderParameters(cdPtr.pptr()));

        // Resolve signature calldata offset, use that to decode and copy from
        // calldata, and write resultant memory offset to head in memory.
        mPtr.offset(Order_signature_offset).write(
            _decodeBytes(cdPtr.pptrOffset(Order_signature_offset))
        );
    }

    /**
     * @dev Takes a calldata pointer to an AdvancedOrder struct and copies the
     *      decoded struct to memory.
     *
     * @param cdPtr A calldata pointer for the AdvancedOrder struct.
     *
     * @return mPtr A memory pointer to the AdvancedOrder struct head.
     */
    function _decodeAdvancedOrder(CalldataPointer cdPtr)
        internal
        pure
        returns (MemoryPointer mPtr)
    {
        // Allocate memory for AdvancedOrder head and OrderParameters head.
        mPtr = malloc(AdvancedOrderPlusOrderParameters_head_size);

        // Use numerator + denominator calldata offset to decode and copy
        // from calldata and write resultant memory offset to head in memory.
        cdPtr.offset(AdvancedOrder_numerator_offset).copy(
            mPtr.offset(AdvancedOrder_numerator_offset),
            AdvancedOrder_fixed_segment_0
        );

        // Get pointer to memory immediately after advanced order.
        MemoryPointer mPtrParameters = mPtr.offset(AdvancedOrder_head_size);

        // Write pptr for advanced order parameters to memory.
        mPtr.write(mPtrParameters);

        // Resolve OrderParameters calldata pointer & write to allocated region.
        _decodeOrderParametersTo(cdPtr.pptr(), mPtrParameters);

        // Resolve signature calldata offset, use that to decode and copy from
        // calldata, and write resultant memory offset to head in memory.
        mPtr.offset(AdvancedOrder_signature_offset).write(
            _decodeBytes(cdPtr.pptrOffset(AdvancedOrder_signature_offset))
        );

        // Resolve extraData calldata offset, use that to decode and copy from
        // calldata, and write resultant memory offset to head in memory.
        mPtr.offset(AdvancedOrder_extraData_offset).write(
            _decodeBytes(cdPtr.pptrOffset(AdvancedOrder_extraData_offset))
        );
    }

    /**
     * @dev Allocates a single word of empty bytes in memory and returns the
     *      pointer to that memory region.
     *
     * @return mPtr The memory pointer to the new empty word in memory.
     */
    function _getEmptyBytesOrArray()
        internal
        pure
        returns (MemoryPointer mPtr)
    {
        mPtr = malloc(OneWord);
        mPtr.write(0);
    }

    /**
     * @dev Takes a calldata pointer to an Order struct and copies the decoded
     *      struct to memory as an AdvancedOrder.
     *
     * @param cdPtr A calldata pointer for the Order struct.
     *
     * @return mPtr A memory pointer to the AdvancedOrder struct head.
     */
    function _decodeOrderAsAdvancedOrder(CalldataPointer cdPtr)
        internal
        pure
        returns (MemoryPointer mPtr)
    {
        // Allocate memory for AdvancedOrder head and OrderParameters head.
        mPtr = malloc(AdvancedOrderPlusOrderParameters_head_size);

        // Get pointer to memory immediately after advanced order.
        MemoryPointer mPtrParameters = mPtr.offset(AdvancedOrder_head_size);

        // Write pptr for advanced order parameters.
        mPtr.write(mPtrParameters);

        // Resolve OrderParameters calldata pointer & write to allocated region.
        _decodeOrderParametersTo(cdPtr.pptr(), mPtrParameters);

        // Write default Order numerator and denominator values (i.e. 1/1).
        mPtr.offset(AdvancedOrder_numerator_offset).write(1);
        mPtr.offset(AdvancedOrder_denominator_offset).write(1);

        // Resolve signature calldata offset, use that to decode and copy from
        // calldata, and write resultant memory offset to head in memory.
        mPtr.offset(AdvancedOrder_signature_offset).write(
            _decodeBytes(cdPtr.pptrOffset(Order_signature_offset))
        );

        // Resolve extraData calldata offset, use that to decode and copy from
        // calldata, and write resultant memory offset to head in memory.
        mPtr.offset(AdvancedOrder_extraData_offset).write(
            _getEmptyBytesOrArray()
        );
    }

    /**
     * @dev Takes a calldata pointer to an array of Order structs and copies the
     *      decoded array to memory as an array of AdvancedOrder structs.
     *
     * @param cdPtrLength A calldata pointer to the start of the orders array in
     *                    calldata which contains the length of the array.
     *
     * @return mPtrLength A memory pointer to the start of the array of advanced
     *                    orders in memory which contains length of the array.
     */
    function _decodeOrdersAsAdvancedOrders(CalldataPointer cdPtrLength)
        internal
        pure
        returns (MemoryPointer mPtrLength)
    {
        // Retrieve length of array, masking to prevent potential overflow.
        uint256 arrLength = cdPtrLength.readMaskedUint256();

        unchecked {
            // Derive offset to the tail based on one word per array element.
            uint256 tailOffset = arrLength << OneWordShift;

            // Add one additional word for the length and allocate memory.
            mPtrLength = malloc(tailOffset + OneWord);

            // Write the length of the array to memory.
            mPtrLength.write(arrLength);

            // Advance to first memory & calldata pointers (e.g. after length).
            MemoryPointer mPtrHead = mPtrLength.next();
            CalldataPointer cdPtrHead = cdPtrLength.next();

            // Iterate over each pointer, word by word, until tail is reached.
            for (uint256 offset = 0; offset < tailOffset; offset += OneWord) {
                // Resolve Order calldata offset, use it to decode and copy from
                // calldata, and write resultant AdvancedOrder offset to memory.
                mPtrHead.offset(offset).write(
                    _decodeOrderAsAdvancedOrder(cdPtrHead.pptrOffset(offset))
                );
            }
        }
    }

    /**
     * @dev Takes a calldata pointer to a criteria proof, or an array bytes32
     *      types, and copies the decoded proof to memory.
     *
     * @param cdPtrLength A calldata pointer to the start of the criteria proof
     *                    in calldata which contains the length of the array.
     *
     * @return mPtrLength A memory pointer to the start of the criteria proof
     *                    in memory which contains length of the array.
     */
    function _decodeCriteriaProof(CalldataPointer cdPtrLength)
        internal
        pure
        returns (MemoryPointer mPtrLength)
    {
        // Retrieve length of array, masking to prevent potential overflow.
        uint256 arrLength = cdPtrLength.readMaskedUint256();

        unchecked {
            // Derive array size based on one word per array element and length.
            uint256 arrSize = (arrLength + 1) << OneWordShift;

            // Allocate memory equal to the array size.
            mPtrLength = malloc(arrSize);

            // Copy the array from calldata into memory.
            cdPtrLength.copy(mPtrLength, arrSize);
        }
    }

    /**
     * @dev Takes a calldata pointer to a CriteriaResolver struct and copies the
     *      decoded struct to memory.
     *
     * @param cdPtr A calldata pointer for the CriteriaResolver struct.
     *
     * @return mPtr A memory pointer to the CriteriaResolver struct head.
     */
    function _decodeCriteriaResolver(CalldataPointer cdPtr)
        internal
        pure
        returns (MemoryPointer mPtr)
    {
        // Allocate required memory for the CriteriaResolver head (the criteria
        // proof bytes32 array is allocated independently).
        mPtr = malloc(CriteriaResolver_head_size);

        // Decode and copy order index, side, index, and identifier from
        // calldata and write resultant memory offset to head in memory.
        cdPtr.copy(mPtr, CriteriaResolver_fixed_segment_0);

        // Resolve criteria proof calldata offset, use it to decode and copy
        // from calldata, and write resultant memory offset to head in memory.
        mPtr.offset(CriteriaResolver_criteriaProof_offset).write(
            _decodeCriteriaProof(
                cdPtr.pptrOffset(CriteriaResolver_criteriaProof_offset)
            )
        );
    }

    /**
     * @dev Takes an array of criteria resolvers from calldata and copies it
     *      into memory.
     *
     * @param cdPtrLength A calldata pointer to the start of the criteria
     *                    resolver array in calldata which contains the length
     *                    of the array.
     *
     * @return mPtrLength A memory pointer to the start of the criteria resolver
     *                    array in memory which contains the length of the
     *                    array.
     */
    function _decodeCriteriaResolvers(CalldataPointer cdPtrLength)
        internal
        pure
        returns (MemoryPointer mPtrLength)
    {
        // Retrieve length of array, masking to prevent potential overflow.
        uint256 arrLength = cdPtrLength.readMaskedUint256();

        unchecked {
            // Derive offset to the tail based on one word per array element.
            uint256 tailOffset = arrLength << OneWordShift;

            // Add one additional word for the length and allocate memory.
            mPtrLength = malloc(tailOffset + OneWord);

            // Write the length of the array to memory.
            mPtrLength.write(arrLength);

            // Advance to first memory & calldata pointers (e.g. after length).
            MemoryPointer mPtrHead = mPtrLength.next();
            CalldataPointer cdPtrHead = cdPtrLength.next();

            // Iterate over each pointer, word by word, until tail is reached.
            for (uint256 offset = 0; offset < tailOffset; offset += OneWord) {
                // Resolve CriteriaResolver calldata offset, use it to decode
                // and copy from calldata, and write resultant memory offset.
                mPtrHead.offset(offset).write(
                    _decodeCriteriaResolver(cdPtrHead.pptrOffset(offset))
                );
            }
        }
    }

    /**
     * @dev Takes an array of orders from calldata and copies it into memory.
     *
     * @param cdPtrLength A calldata pointer to the start of the orders array in
     *                    calldata which contains the length of the array.
     *
     * @return mPtrLength A memory pointer to the start of the orders array
     *                    in memory which contains the length of the array.
     */
    function _decodeOrders(CalldataPointer cdPtrLength)
        internal
        pure
        returns (MemoryPointer mPtrLength)
    {
        // Retrieve length of array, masking to prevent potential overflow.
        uint256 arrLength = cdPtrLength.readMaskedUint256();

        unchecked {
            // Derive offset to the tail based on one word per array element.
            uint256 tailOffset = arrLength << OneWordShift;

            // Add one additional word for the length and allocate memory.
            mPtrLength = malloc(tailOffset + OneWord);

            // Write the length of the array to memory.
            mPtrLength.write(arrLength);

            // Advance to first memory & calldata pointers (e.g. after length).
            MemoryPointer mPtrHead = mPtrLength.next();
            CalldataPointer cdPtrHead = cdPtrLength.next();

            // Iterate over each pointer, word by word, until tail is reached.
            for (uint256 offset = 0; offset < tailOffset; offset += OneWord) {
                // Resolve Order calldata offset, use it to decode and copy
                // from calldata, and write resultant memory offset.
                mPtrHead.offset(offset).write(
                    _decodeOrder(cdPtrHead.pptrOffset(offset))
                );
            }
        }
    }

    /**
     * @dev Takes an array of fulfillment components from calldata and copies it
     *      into memory.
     *
     * @param cdPtrLength A calldata pointer to the start of the fulfillment
     *                    components array in calldata which contains the length
     *                    of the array.
     *
     * @return mPtrLength A memory pointer to the start of the fulfillment
     *                    components array in memory which contains the length
     *                    of the array.
     */
    function _decodeFulfillmentComponents(CalldataPointer cdPtrLength)
        internal
        pure
        returns (MemoryPointer mPtrLength)
    {
        assembly {
            let arrLength := and(calldataload(cdPtrLength), OffsetOrLengthMask)

            // Get the current free memory pointer.
            mPtrLength := mload(FreeMemoryPointerSlot)

            mstore(mPtrLength, arrLength)
            let mPtrHead := add(mPtrLength, OneWord)
            let mPtrTail := add(mPtrHead, shl(OneWordShift, arrLength))
            let mPtrTailNext := mPtrTail
            calldatacopy(
                mPtrTail,
                add(cdPtrLength, OneWord),
                shl(FulfillmentComponent_mem_tail_size_shift, arrLength)
            )
            let mPtrHeadNext := mPtrHead
            for { } lt(mPtrHeadNext, mPtrTail) { } {
                mstore(mPtrHeadNext, mPtrTailNext)
                mPtrHeadNext := add(mPtrHeadNext, OneWord)
                mPtrTailNext :=
                    add(mPtrTailNext, FulfillmentComponent_mem_tail_size)
            }

            // Update the free memory pointer.
            mstore(FreeMemoryPointerSlot, mPtrTailNext)
        }
    }

    /**
     * @dev Takes a nested array of fulfillment components from calldata and
     *      copies it into memory.
     *
     * @param cdPtrLength A calldata pointer to the start of the nested
     *                    fulfillment components array in calldata which
     *                    contains the length of the array.
     *
     * @return mPtrLength A memory pointer to the start of the nested
     *                    fulfillment components array in memory which
     *                    contains the length of the array.
     */
    function _decodeNestedFulfillmentComponents(CalldataPointer cdPtrLength)
        internal
        pure
        returns (MemoryPointer mPtrLength)
    {
        // Retrieve length of array, masking to prevent potential overflow.
        uint256 arrLength = cdPtrLength.readMaskedUint256();

        unchecked {
            // Derive offset to the tail based on one word per array element.
            uint256 tailOffset = arrLength << OneWordShift;

            // Add one additional word for the length and allocate memory.
            mPtrLength = malloc(tailOffset + OneWord);

            // Write the length of the array to memory.
            mPtrLength.write(arrLength);

            // Advance to first memory & calldata pointers (e.g. after length).
            MemoryPointer mPtrHead = mPtrLength.next();
            CalldataPointer cdPtrHead = cdPtrLength.next();

            // Iterate over each pointer, word by word, until tail is reached.
            for (uint256 offset = 0; offset < tailOffset; offset += OneWord) {
                // Resolve FulfillmentComponents array calldata offset, use it
                // to decode and copy from calldata, and write memory offset.
                mPtrHead.offset(offset).write(
                    _decodeFulfillmentComponents(cdPtrHead.pptrOffset(offset))
                );
            }
        }
    }

    /**
     * @dev Takes an array of advanced orders from calldata and copies it into
     *      memory.
     *
     * @param cdPtrLength A calldata pointer to the start of the advanced orders
     *                    array in calldata which contains the length of the
     *                    array.
     *
     * @return mPtrLength A memory pointer to the start of the advanced orders
     *                    array in memory which contains the length of the
     *                    array.
     */
    function _decodeAdvancedOrders(CalldataPointer cdPtrLength)
        internal
        pure
        returns (MemoryPointer mPtrLength)
    {
        // Retrieve length of array, masking to prevent potential overflow.
        uint256 arrLength = cdPtrLength.readMaskedUint256();

        unchecked {
            // Derive offset to the tail based on one word per array element.
            uint256 tailOffset = arrLength << OneWordShift;

            // Add one additional word for the length and allocate memory.
            mPtrLength = malloc(tailOffset + OneWord);

            // Write the length of the array to memory.
            mPtrLength.write(arrLength);

            // Advance to first memory & calldata pointers (e.g. after length).
            MemoryPointer mPtrHead = mPtrLength.next();
            CalldataPointer cdPtrHead = cdPtrLength.next();

            // Iterate over each pointer, word by word, until tail is reached.
            for (uint256 offset = 0; offset < tailOffset; offset += OneWord) {
                // Resolve AdvancedOrder calldata offset, use it to decode and
                // copy from calldata, and write resultant memory offset.
                mPtrHead.offset(offset).write(
                    _decodeAdvancedOrder(cdPtrHead.pptrOffset(offset))
                );
            }
        }
    }

    /**
     * @dev Takes a calldata pointer to a Fulfillment struct and copies the
     *      decoded struct to memory.
     *
     * @param cdPtr A calldata pointer for the Fulfillment struct.
     *
     * @return mPtr A memory pointer to the Fulfillment struct head.
     */
    function _decodeFulfillment(CalldataPointer cdPtr)
        internal
        pure
        returns (MemoryPointer mPtr)
    {
        // Allocate required memory for the Fulfillment head (the fulfillment
        // components arrays are allocated independently).
        mPtr = malloc(Fulfillment_head_size);

        // Resolve offerComponents calldata offset, use it to decode and copy
        // from calldata, and write resultant memory offset to head in memory.
        mPtr.write(_decodeFulfillmentComponents(cdPtr.pptr()));

        // Resolve considerationComponents calldata offset, use it to decode and
        // copy from calldata, and write resultant memory offset to memory head.
        mPtr.offset(Fulfillment_considerationComponents_offset).write(
            _decodeFulfillmentComponents(
                cdPtr.pptrOffset(Fulfillment_considerationComponents_offset)
            )
        );
    }

    /**
     * @dev Takes an array of fulfillments from calldata and copies it into
     *      memory.
     *
     * @param cdPtrLength A calldata pointer to the start of the fulfillments
     *                    array in calldata which contains the length of the
     *                    array.
     *
     * @return mPtrLength A memory pointer to the start of the fulfillments
     *                    array in memory which contains the length of the
     *                    array.
     */
    function _decodeFulfillments(CalldataPointer cdPtrLength)
        internal
        pure
        returns (MemoryPointer mPtrLength)
    {
        // Retrieve length of array, masking to prevent potential overflow.
        uint256 arrLength = cdPtrLength.readMaskedUint256();

        unchecked {
            // Derive offset to the tail based on one word per array element.
            uint256 tailOffset = arrLength << OneWordShift;

            // Add one additional word for the length and allocate memory.
            mPtrLength = malloc(tailOffset + OneWord);

            // Write the length of the array to memory.
            mPtrLength.write(arrLength);

            // Advance to first memory & calldata pointers (e.g. after length).
            MemoryPointer mPtrHead = mPtrLength.next();
            CalldataPointer cdPtrHead = cdPtrLength.next();

            // Iterate over each pointer, word by word, until tail is reached.
            for (uint256 offset = 0; offset < tailOffset; offset += OneWord) {
                // Resolve Fulfillment calldata offset, use it to decode and
                // copy from calldata, and write resultant memory offset.
                mPtrHead.offset(offset).write(
                    _decodeFulfillment(cdPtrHead.pptrOffset(offset))
                );
            }
        }
    }

    /**
     * @dev Takes a calldata pointer to an OrderComponents struct and copies the
     *      decoded struct to memory as an OrderParameters struct (with the
     *      totalOriginalConsiderationItems value set equal to the length of the
     *      supplied consideration array).
     *
     * @param cdPtr A calldata pointer for the OrderComponents struct.
     *
     * @return mPtr A memory pointer to the OrderParameters struct head.
     */
    function _decodeOrderComponentsAsOrderParameters(CalldataPointer cdPtr)
        internal
        pure
        returns (MemoryPointer mPtr)
    {
        // Allocate memory for the OrderParameters head.
        mPtr = malloc(OrderParameters_head_size);

        // Copy the full OrderComponents head from calldata to memory.
        cdPtr.copy(mPtr, OrderComponents_OrderParameters_common_head_size);

        // Resolve the offer calldata offset, use that to decode and copy offer
        // from calldata, and write resultant memory offset to head in memory.
        mPtr.offset(OrderParameters_offer_head_offset).write(
            _decodeOffer(cdPtr.pptrOffset(OrderParameters_offer_head_offset))
        );

        // Resolve consideration calldata offset, use that to copy consideration
        // from calldata, and write resultant memory offset to head in memory.
        MemoryPointer consideration = _decodeConsideration(
            cdPtr.pptrOffset(OrderParameters_consideration_head_offset)
        );
        mPtr.offset(OrderParameters_consideration_head_offset).write(
            consideration
        );

        // Write masked consideration length to totalOriginalConsiderationItems.
        mPtr.offset(OrderParameters_totalOriginalConsiderationItems_offset)
            .write(consideration.readUint256());
    }

    /**
     * @dev Decodes the returndata from a call to generateOrder, or returns
     *      empty arrays and a boolean signifying that the returndata does not
     *      adhere to a valid encoding scheme if it cannot be decoded. Note
     *      that this function expects that original offer and consideration
     *      item arrays have been modified and repurposed to resemble spent
     *      and received item arrays; specifically, the recipient should be
     *      in the endAmount location on consideration items and the derived
     *      amount should be in the startAmount location for both item types.
     *
     * @return invalidEncoding A boolean signifying whether the returndata has
     *                         an invalid encoding.
     * @return offer           The decoded offer array.
     * @return consideration   The decoded consideration array.
     */
    function _decodeGenerateOrderReturndata(
        MemoryPointer originalOffer,
        MemoryPointer originalConsideration
    )
        internal
        pure
        returns (
            uint256 invalidEncoding,
            MemoryPointer offer,
            MemoryPointer consideration
        )
    {
        assembly {
            // Check that returndatasize is at least three words: 
            // 1. offerOffset
            // 2. considerationOffset
            // 3. offerLength & considerationLength might occupy just one word
            //    if offerOffset & considerationOffset would point to the same
            //    offset and the arrays have length 0.
            invalidEncoding := lt(returndatasize(), ThreeWords)

            let offsetOffer
            let offsetConsideration
            let offerLength
            let considerationLength

            // Proceed if enough returndata is present to continue evaluation.
            if iszero(invalidEncoding) {
                // Copy first two words of returndata (the offsets to offer and
                // consideration array lengths) to scratch space.
                returndatacopy(0, 0, TwoWords)
                offsetOffer := mload(0)
                offsetConsideration := mload(OneWord)

                // If valid length, check that offsets word boundaries are
                // within returndata.
                let invalidOfferOffset :=
                    gt(
                        add(offsetOffer, OneWord), 
                        returndatasize()
                    )
                let invalidConsiderationOffset :=
                    gt(
                        add(offsetConsideration, OneWord),
                        returndatasize()
                    )

                // Only proceed if length (and thus encoding) is valid so far.
                invalidEncoding :=
                    or(invalidOfferOffset, invalidConsiderationOffset)
                if iszero(invalidEncoding) {
                    // Copy length of offer array to scratch space.
                    returndatacopy(0, offsetOffer, OneWord)
                    offerLength := mload(0)

                    // Copy length of consideration array to scratch space.
                    returndatacopy(OneWord, offsetConsideration, OneWord)
                    considerationLength := mload(OneWord)

                    {
                        // Derive end offsets for offer & consideration arrays.
                        let offerEndOffset :=
                            add(
                                add(offsetOffer, OneWord),
                                shl(SpentItem_size_shift, offerLength)
                            )
                        let considerationEndOffset :=
                            add(
                                add(offsetConsideration, OneWord),
                                mul(ReceivedItem_size, considerationLength)
                            )

                        // Don't continue if either offer or consideration
                        // length exceeds 65535 or if returndatasize is less
                        // than the end offsets.
                        invalidEncoding :=
                            or(
                                gt(
                                    or(offerLength, considerationLength),
                                    generateOrder_maximum_returned_array_length
                                ),
                                or(
                                    lt(returndatasize(), offerEndOffset),
                                    lt(returndatasize(), considerationEndOffset)
                                )
                            )

                        // Set first word of scratch space to 0 so length of
                        // offer/consideration are set to 0 on invalid encoding.
                        mstore(0, 0)
                    }
                }
            }

            if iszero(invalidEncoding) {
                let invalidSpentItems, invalidReceivedItems
                offer, invalidSpentItems :=
                    copySpentItemsAsOfferItems(
                        originalOffer,
                        add(offsetOffer, OneWord),
                        offerLength
                    )

                consideration, invalidReceivedItems :=
                    copyReceivedItemsAsConsiderationItems(
                        originalConsideration,
                        add(offsetConsideration, OneWord),
                        considerationLength
                    )
                invalidEncoding := or(invalidSpentItems, invalidReceivedItems)
            }

            function copySpentItemsAsOfferItems(
                mPtrLengthOriginal, rdPtrHeadSpentItems, length
            ) -> mPtrLength, invalidSpentItems
            {
                // Retrieve the current free memory pointer.
                mPtrLength := mload(FreeMemoryPointerSlot)

                // Cache the original offer array length
                let originalOfferLength := mload(mPtrLengthOriginal)

                // Allocate memory for the new array.
                mstore(
                    FreeMemoryPointerSlot,
                    add(
                        mPtrLength,
                        add(
                            OneWord,
                            mul(length, OfferItem_size_with_head_pointer)
                        )
                    )
                )

                // Write the length of the array to the start of free memory.
                mstore(mPtrLength, length)

                // Use offset from length to minimize stack depth.
                let headOffsetFromLength := OneWord
                let headSizeWithLength := shl(OneWordShift, add(1, length))
                let mPtrTailNext := add(mPtrLength, headSizeWithLength)
                let mPtrTailOriginalNext := add(
                    mPtrLengthOriginal,
                    shl(OneWordShift, add(1, originalOfferLength))
                )

                let headSizeToCompareWithLength := shl(
                    OneWordShift,
                    add(1, min(length, originalOfferLength))
                )

                // Iterate over each new element with a corresponding original
                // item. For each original offer item, check that:
                // - There is a corresponding new spent item.
                // - The original and new items match with compareItems.
                // - The new offer item amount >= original amount.
                invalidSpentItems := gt(originalOfferLength, length)
                for { } lt(
                    headOffsetFromLength, headSizeToCompareWithLength
                ) { } {
                    // Write the memory pointer to the accompanying head offset.
                    mstore(add(mPtrLength, headOffsetFromLength), mPtrTailNext)

                    // Copy itemType, token, identifier and amount.
                    returndatacopy(
                        mPtrTailNext,
                        rdPtrHeadSpentItems,
                        SpentItem_size
                    )

                    let newAmount := mload(
                        add(mPtrTailNext, Common_amount_offset)
                    )

                    // Copy amount to endAmount.
                    mstore(
                        add(mPtrTailNext, Common_endAmount_offset),
                        newAmount
                    )

                    let originalAmount := mload(
                        add(mPtrTailOriginalNext, Common_amount_offset)
                    )
                    invalidSpentItems := or(
                        invalidSpentItems,
                        or(
                            compareItems(mPtrTailOriginalNext, mPtrTailNext),
                            gt(originalAmount, newAmount)
                        )
                    )

                    // Update read pointer, next tail pointer for new and
                    // original, and head offset.
                    rdPtrHeadSpentItems := add(
                        rdPtrHeadSpentItems,
                        SpentItem_size
                    )
                    mPtrTailNext := add(mPtrTailNext, OfferItem_size)
                    mPtrTailOriginalNext := add(
                        mPtrTailOriginalNext,
                        OfferItem_size
                    )
                    headOffsetFromLength := add(headOffsetFromLength, OneWord)
                }

                // Iterate over each element without corresponding original item
                for { } lt(headOffsetFromLength, headSizeWithLength) { } {
                    // Write the memory pointer to the accompanying head offset.
                    mstore(add(mPtrLength, headOffsetFromLength), mPtrTailNext)

                    // Copy itemType, token, identifier and amount.
                    returndatacopy(
                        mPtrTailNext,
                        rdPtrHeadSpentItems,
                        SpentItem_size
                    )

                    // Copy amount to endAmount.
                    mstore(
                        add(mPtrTailNext, Common_endAmount_offset),
                        mload(add(mPtrTailNext, Common_amount_offset))
                    )

                    // Update read pointer, next tail pointer, and head offset.
                    rdPtrHeadSpentItems := add(
                        rdPtrHeadSpentItems,
                        SpentItem_size
                    )
                    mPtrTailNext := add(mPtrTailNext, OfferItem_size)
                    headOffsetFromLength := add(headOffsetFromLength, OneWord)
                }
            }

            function copyReceivedItemsAsConsiderationItems(
                mPtrLengthOriginal, rdPtrHeadReceivedItems, length
            ) -> mPtrLength, invalidReceivedItems
            {
                // Retrieve the current free memory pointer.
                mPtrLength := mload(FreeMemoryPointerSlot)
                // Cache the original consideration array length
                let originalConsiderationLength := mload(mPtrLengthOriginal)

                // Ensure returned array length does not exceed original length.
                invalidReceivedItems := gt(length, originalConsiderationLength)

                // Derive the length of the new array in memory, capped by the
                // original consideration array length.
                let newLength := min(length, originalConsiderationLength)

                // Allocate memory for the array. Note that memory does not need
                // to be allocated for new elements without a corresponding
                // original item as the new array will be invalid if its length
                // exceeds the original array length. 
                mstore(
                    FreeMemoryPointerSlot,
                    add(
                        mPtrLength,
                        add(
                            OneWord,
                            mul(
                                newLength,
                                ConsiderationItem_size_with_head_pointer
                            )
                        )
                    )
                )

                // Write the length of the array to the start of free memory.
                mstore(mPtrLength, newLength)

                // Use offset from length to minimize stack depth.
                let headOffsetFromLength := OneWord
                let mPtrTailNext := add(
                    mPtrLength,
                    shl(OneWordShift, add(1, newLength))
                )
                let mPtrTailOriginalNext := add(
                    mPtrLengthOriginal,
                    shl(OneWordShift, add(1, originalConsiderationLength))
                )

                let headSizeToCompareWithLength := shl(
                    OneWordShift,
                    add(1, newLength)
                )

                // Iterate over each new element with a corresponding original
                // item. For each new received item, check that:
                // - The new & original items match according to compareItems.
                // - The new consideration item amount <= the original amount.
                // - The items have the same recipient if original != null.
                for { } lt(
                    headOffsetFromLength,
                    headSizeToCompareWithLength
                ) { } {
                    // Write the memory pointer to the accompanying head offset.
                    mstore(add(mPtrLength, headOffsetFromLength), mPtrTailNext)

                    // Copy itemType, token, identifier, amount and recipient.
                    returndatacopy(
                        mPtrTailNext,
                        rdPtrHeadReceivedItems,
                        ReceivedItem_size
                    )

                    // Copy amount to consideration item's recipient offset.
                    returndatacopy(
                        add(mPtrTailNext, ConsiderationItem_recipient_offset),
                        add(rdPtrHeadReceivedItems, Common_amount_offset),
                        OneWord
                    )

                    // Retrieve both the new and original item amounts.
                    let newAmount := mload(
                        add(mPtrTailNext, Common_amount_offset)
                    )
                    let originalAmount := mload(
                        add(mPtrTailOriginalNext, Common_amount_offset)
                    )

                    // Compare items' item type, token, and identifier, ensure
                    // they have the same recipient and that the new amount is
                    // less than or equal to the original amount. The original
                    // recipient must already be present at the ReceivedItem
                    // recipient offset rather than at the initial
                    // ConsiderationItem recipient offset.
                    invalidReceivedItems := or(
                        invalidReceivedItems,
                        or(
                            compareItems(mPtrTailOriginalNext, mPtrTailNext),
                            or(
                                gt(newAmount, originalAmount),
                                checkRecipients(
                                    mload(
                                        add(
                                            mPtrTailOriginalNext,
                                            ReceivedItem_recipient_offset
                                        )
                                    ),
                                    mload(
                                        add(
                                            mPtrTailNext,
                                            ReceivedItem_recipient_offset
                                        )
                                    )
                                )
                            )
                        )
                    )

                    // Update read pointer, next tail pointer, and head offset.
                    rdPtrHeadReceivedItems := add(
                        rdPtrHeadReceivedItems,
                        ReceivedItem_size
                    )
                    mPtrTailNext := add(mPtrTailNext, ConsiderationItem_size)
                    mPtrTailOriginalNext := add(
                        mPtrTailOriginalNext,
                        ConsiderationItem_size
                    )
                    headOffsetFromLength := add(headOffsetFromLength, OneWord)
                }

                // Note: skip copying new elements without a corresponding
                // original item as the new array will be invalid if its length
                // exceeds the original array length.
            }

            /**
             * @dev Yul function to check the compatibility of two offer or
             *      consideration items for contract orders.  Note that the
             *      itemType and identifier are reset in cases where criteria is
             *      equal to 0 (collection-wide or "wildcard" items), which
             *      means that a contract offerer has full latitude to choose
             *      any identifier it wants mid-flight, in contrast to the usual
             *      behavior, where the fulfiller can pick which identifier to
             *      receive by providing a CriteriaResolver.
             *
             * @param originalItem The original offer or consideration item.
             * @param newItem      The new offer or consideration item.
             *
             * @return isInvalid Error buffer indicating whether or not the
             *                   items are incompatible.
             */
            function compareItems(originalItem, newItem) -> isInvalid {
                let itemType := mload(originalItem)
                let identifier := mload(
                    add(originalItem, Common_identifier_offset)
                )

                // Use returned identifier for criteria-based items with a
                // criteria value of 0 (collection-wide or "wildcard" items).
                if and(gt(itemType, 3), iszero(identifier)) {
                    // Replace item type with non-criteria equivalent.
                    itemType := sub(itemType, 2)

                    // Replace identifier with the returned identifier.
                    identifier := mload(add(newItem, Common_identifier_offset))
                }

                isInvalid :=
                    iszero(
                        and(
                            // originalItem.token == newItem.token &&
                            // originalItem.itemType == newItem.itemType
                            and(
                                eq(
                                    mload(
                                        add(originalItem, Common_token_offset)
                                    ),
                                    mload(add(newItem, Common_token_offset))
                                ),
                                eq(itemType, mload(newItem))
                            ),
                            // originalItem.identifier == newItem.identifier
                            eq(
                                identifier,
                                mload(add(newItem, Common_identifier_offset))
                            )

                        )
                    )
            }

            /**
             * @dev Internal pure function to check the compatibility of two
             *      recipients on consideration items for contract orders. This
             *      check is skipped if no recipient is originally supplied.
             *
             * @param originalRecipient The original consideration item
             *                          recipient.
             * @param newRecipient      The new consideration item recipient.
             *
             * @return isInvalid Error buffer indicating whether or not the
             *                   two recipients are incompatible.
             */
            function checkRecipients(
                originalRecipient,
                newRecipient
            ) -> isInvalid {
                isInvalid :=
                    iszero(
                        or(
                            iszero(originalRecipient),
                            eq(newRecipient, originalRecipient)
                        )
                    )
            }

            function min(a, b) -> c {
                c := add(b, mul(lt(a, b), sub(a, b)))
            }
        }
    }

    /**
     * @dev Converts a function returning _decodeGenerateOrderReturndata types
     *      into a function returning offer and consideration types.
     *
     * @param inFn The input function, taking no arguments and returning an
     *             error buffer, spent item array, and received item array.
     *
     * @return outFn The output function, taking no arguments and returning an
     *               error buffer, offer array, and consideration array.
     */
    function _convertGetGeneratedOrderResult(
        function(MemoryPointer, MemoryPointer)
            internal
            pure
            returns (uint256, MemoryPointer, MemoryPointer) inFn
    )
        internal
        pure
        returns (
            function(
                OfferItem[] memory,
                ConsiderationItem[] memory
            ) internal pure returns (
                uint256,
                OfferItem[] memory,
                ConsiderationItem[] memory
            ) outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Converts a function taking ReceivedItem, address, bytes32, and bytes
     *      types (e.g. the _transfer function) into a function taking
     *      OfferItem, address, bytes32, and bytes types.
     *
     * @param inFn The input function, taking ReceivedItem, address, bytes32,
     *             and bytes types (e.g. the _transfer function).
     *
     * @return outFn The output function, taking OfferItem, address, bytes32,
     *               and bytes types.
     */
    function _toOfferItemInput(
        function(
            ReceivedItem memory,
            address,
            bytes32,
            bytes memory
        ) internal inFn
    )
        internal
        pure
        returns (
            function(
                OfferItem memory,
                address,
                bytes32,
                bytes memory
            ) internal outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Converts a function taking ReceivedItem, address, bytes32, and bytes
     *      types (e.g. the _transfer function) into a function taking
     *      ConsiderationItem, address, bytes32, and bytes types.
     *
     * @param inFn The input function, taking ReceivedItem, address, bytes32,
     *             and bytes types (e.g. the _transfer function).
     *
     * @return outFn The output function, taking ConsiderationItem, address,
     *               bytes32, and bytes types.
     */
    function _toConsiderationItemInput(
        function(
            ReceivedItem memory,
            address,
            bytes32,
            bytes memory
        ) internal inFn
    )
        internal
        pure
        returns (
            function(
                ConsiderationItem memory,
                address,
                bytes32,
                bytes memory
            ) internal outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Converts a function taking a calldata pointer and returning a memory
     *      pointer into a function taking that calldata pointer and returning
     *      a bytes type.
     *
     * @param inFn The input function, taking an arbitrary calldata pointer and
     *             returning an arbitrary memory pointer.
     *
     * @return outFn The output function, taking an arbitrary calldata pointer
     *               and returning a bytes type.
     */
    function _toBytesReturnType(
        function(CalldataPointer) internal pure returns (MemoryPointer) inFn
    )
        internal
        pure
        returns (
            function(
                CalldataPointer
            ) internal pure returns (
                bytes memory
            ) outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Converts a function taking a calldata pointer and returning a memory
     *      pointer into a function taking that calldata pointer and returning
     *      an OrderParameters type.
     *
     * @param inFn The input function, taking an arbitrary calldata pointer and
     *             returning an arbitrary memory pointer.
     *
     * @return outFn The output function, taking an arbitrary calldata pointer
     *               and returning an OrderParameters type.
     */
    function _toOrderParametersReturnType(
        function(CalldataPointer) internal pure returns (MemoryPointer) inFn
    )
        internal
        pure
        returns (
            function(
                CalldataPointer
            ) internal pure returns (
                OrderParameters memory
            ) outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Converts a function taking a calldata pointer and returning a memory
     *      pointer into a function taking that calldata pointer and returning
     *      an AdvancedOrder type.
     *
     * @param inFn The input function, taking an arbitrary calldata pointer and
     *             returning an arbitrary memory pointer.
     *
     * @return outFn The output function, taking an arbitrary calldata pointer
     *               and returning an AdvancedOrder type.
     */
    function _toAdvancedOrderReturnType(
        function(CalldataPointer) internal pure returns (MemoryPointer) inFn
    )
        internal
        pure
        returns (
            function(
                CalldataPointer
            ) internal pure returns (
                AdvancedOrder memory
            )  outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Converts a function taking a calldata pointer and returning a memory
     *      pointer into a function taking that calldata pointer and returning
     *      a dynamic array of CriteriaResolver types.
     *
     * @param inFn The input function, taking an arbitrary calldata pointer and
     *             returning an arbitrary memory pointer.
     *
     * @return outFn The output function, taking an arbitrary calldata pointer
     *               and returning a dynamic array of CriteriaResolver types.
     */
    function _toCriteriaResolversReturnType(
        function(CalldataPointer) internal pure returns (MemoryPointer) inFn
    )
        internal
        pure
        returns (
            function(
                CalldataPointer
            ) internal pure returns (
                CriteriaResolver[] memory
            ) outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Converts a function taking a calldata pointer and returning a memory
     *      pointer into a function taking that calldata pointer and returning
     *      a dynamic array of Order types.
     *
     * @param inFn The input function, taking an arbitrary calldata pointer and
     *             returning an arbitrary memory pointer.
     *
     * @return outFn The output function, taking an arbitrary calldata pointer
     *               and returning a dynamic array of Order types.
     */
    function _toOrdersReturnType(
        function(CalldataPointer) internal pure returns (MemoryPointer) inFn
    )
        internal
        pure
        returns (
            function(
                CalldataPointer
            ) internal pure returns (
                Order[] memory
            ) outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Converts a function taking a calldata pointer and returning a memory
     *      pointer into a function taking that calldata pointer and returning
     *      a nested dynamic array of dynamic arrays of FulfillmentComponent
     *      types.
     *
     * @param inFn The input function, taking an arbitrary calldata pointer and
     *             returning an arbitrary memory pointer.
     *
     * @return outFn The output function, taking an arbitrary calldata pointer
     *               and returning a nested dynamic array of dynamic arrays of
     *               FulfillmentComponent types.
     */
    function _toNestedFulfillmentComponentsReturnType(
        function(CalldataPointer) internal pure returns (MemoryPointer) inFn
    )
        internal
        pure
        returns (
            function(
                CalldataPointer
            ) internal pure returns (
                FulfillmentComponent[][] memory
            ) outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Converts a function taking a calldata pointer and returning a memory
     *      pointer into a function taking that calldata pointer and returning
     *      a dynamic array of AdvancedOrder types.
     *
     * @param inFn The input function, taking an arbitrary calldata pointer and
     *             returning an arbitrary memory pointer.
     *
     * @return outFn The output function, taking an arbitrary calldata pointer
     *               and returning a dynamic array of AdvancedOrder types.
     */
    function _toAdvancedOrdersReturnType(
        function(CalldataPointer) internal pure returns (MemoryPointer) inFn
    )
        internal
        pure
        returns (
            function(
                CalldataPointer
            ) internal pure returns (
                AdvancedOrder[] memory
            ) outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Converts a function taking a calldata pointer and returning a memory
     *      pointer into a function taking that calldata pointer and returning
     *      a dynamic array of Fulfillment types.
     *
     * @param inFn The input function, taking an arbitrary calldata pointer and
     *             returning an arbitrary memory pointer.
     *
     * @return outFn The output function, taking an arbitrary calldata pointer
     *               and returning a dynamic array of Fulfillment types.
     */
    function _toFulfillmentsReturnType(
        function(CalldataPointer) internal pure returns (MemoryPointer) inFn
    )
        internal
        pure
        returns (
            function(
                CalldataPointer
            ) internal pure returns (
                Fulfillment[] memory
            ) outFn
        )
    {
        assembly {
            outFn := inFn
        }
    }

    /**
     * @dev Caches the endAmount in an offer item and replaces it with
     * a given recipient so that its memory may be reused as a temporary
     * ReceivedItem.
     *
     * @param offerItem The offer item.
     * @param recipient The recipient.
     *
     * @return originalEndAmount The original end amount.
     */
    function _replaceEndAmountWithRecipient(
        OfferItem memory offerItem,
        address recipient
    ) internal pure returns (uint256 originalEndAmount) {
        assembly {
            // Derive the pointer to the end amount on the offer item.
            let endAmountPtr := add(offerItem, ReceivedItem_recipient_offset)

            // Retrieve the value of the end amount on the offer item.
            originalEndAmount := mload(endAmountPtr)

            // Write recipient to received item at the offer end amount pointer.
            mstore(endAmountPtr, recipient)
        }
    }
}
