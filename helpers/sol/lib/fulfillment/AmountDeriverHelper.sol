// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AmountDeriver } from "../../../../lib/AmountDeriver.sol";
import {
    OfferItem,
    Order,
    ConsiderationItem,
    OrderParameters,
    AdvancedOrder,
    SpentItem,
    ReceivedItem,
    CriteriaResolver
} from "../../../../lib/ConsiderationStructs.sol";
import { Side, ItemType } from "../../../../lib/ConsiderationEnums.sol";
import { OfferItemLib } from "../OfferItemLib.sol";
import { ConsiderationItemLib } from "../ConsiderationItemLib.sol";
import { OrderParametersLib } from "../OrderParametersLib.sol";
import { OrderDetails } from "../../fulfillments/lib/Structs.sol";

/**
 * @notice Note that this contract relies on current block.timestamp to determine amounts.
 */
contract AmountDeriverHelper is AmountDeriver {
    using OfferItemLib for OfferItem[];
    using ConsiderationItemLib for ConsiderationItem[];
    using OrderParametersLib for OrderParameters;

    function getSpentAndReceivedItems(
        Order calldata order
    )
        external
        view
        returns (SpentItem[] memory spent, ReceivedItem[] memory received)
    {
        return getSpentAndReceivedItems(order.parameters);
    }

    function getSpentAndReceivedItems(
        AdvancedOrder calldata order
    )
        external
        view
        returns (SpentItem[] memory spent, ReceivedItem[] memory received)
    {
        CriteriaResolver[] memory resolvers;
        return
            getSpentAndReceivedItems(
                order.parameters,
                order.numerator,
                order.denominator,
                0,
                resolvers
            );
    }

    function getSpentAndReceivedItems(
        AdvancedOrder calldata order,
        uint256 orderIndex,
        CriteriaResolver[] calldata criteriaResolvers
    )
        external
        view
        returns (SpentItem[] memory spent, ReceivedItem[] memory received)
    {
        return
            getSpentAndReceivedItems(
                order.parameters,
                order.numerator,
                order.denominator,
                orderIndex,
                criteriaResolvers
            );
    }

    function getSpentAndReceivedItems(
        OrderParameters calldata parameters
    )
        public
        view
        returns (SpentItem[] memory spent, ReceivedItem[] memory received)
    {
        spent = getSpentItems(parameters);
        received = getReceivedItems(parameters);
    }

    function toOrderDetails(
        OrderParameters memory order
    ) internal view returns (OrderDetails memory) {
        (SpentItem[] memory offer, ReceivedItem[] memory consideration) = this
            .getSpentAndReceivedItems(order);
        return
            OrderDetails({
                offerer: order.offerer,
                conduitKey: order.conduitKey,
                offer: offer,
                consideration: consideration
            });
    }

    function toOrderDetails(
        Order[] memory order
    ) public view returns (OrderDetails[] memory) {
        OrderDetails[] memory orderDetails = new OrderDetails[](order.length);
        for (uint256 i = 0; i < order.length; i++) {
            orderDetails[i] = toOrderDetails(order[i].parameters);
        }
        return orderDetails;
    }

    function toOrderDetails(
        AdvancedOrder[] memory orders,
        CriteriaResolver[] memory resolvers
    ) public view returns (OrderDetails[] memory) {
        OrderDetails[] memory orderDetails = new OrderDetails[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            orderDetails[i] = toOrderDetails(orders[i], i, resolvers);
        }
        return orderDetails;
    }

    function toOrderDetails(
        AdvancedOrder memory order,
        uint256 orderIndex,
        CriteriaResolver[] memory resolvers
    ) internal view returns (OrderDetails memory) {
        (SpentItem[] memory offer, ReceivedItem[] memory consideration) = this
            .getSpentAndReceivedItems(order, orderIndex, resolvers);
        return
            OrderDetails({
                offerer: order.parameters.offerer,
                conduitKey: order.parameters.conduitKey,
                offer: offer,
                consideration: consideration
            });
    }

    function getSpentAndReceivedItems(
        OrderParameters memory parameters,
        uint256 numerator,
        uint256 denominator,
        uint256 orderIndex,
        CriteriaResolver[] memory criteriaResolvers
    )
        private
        view
        returns (SpentItem[] memory spent, ReceivedItem[] memory received)
    {
        // create a deep copy of parameters to avoid modifying the original
        parameters = parameters.copy();
        applyCriteriaResolvers(parameters, orderIndex, criteriaResolvers);

        spent = getSpentItems(parameters, numerator, denominator);
        received = getReceivedItems(parameters, numerator, denominator);
    }

    function convertCriteriaItemType(
        ItemType itemType
    ) internal pure returns (ItemType) {
        if (itemType == ItemType.ERC721_WITH_CRITERIA) {
            return ItemType.ERC721;
        } else if (itemType == ItemType.ERC1155_WITH_CRITERIA) {
            return ItemType.ERC1155;
        } else {
            revert("amount deriver helper resolving non criteria item type");
        }
    }

    function applyCriteriaResolvers(
        OrderParameters memory parameters,
        uint256 orderIndex,
        CriteriaResolver[] memory criteriaResolvers
    ) private pure {
        OfferItem[] memory offer = parameters.offer;
        ConsiderationItem[] memory consideration = parameters.consideration;
        for (uint256 i = 0; i < criteriaResolvers.length; i++) {
            CriteriaResolver memory resolver = criteriaResolvers[i];
            if (resolver.orderIndex != orderIndex) {
                continue;
            }
            if (resolver.side == Side.OFFER) {
                OfferItem memory item = offer[resolver.index];
                item.itemType = convertCriteriaItemType(item.itemType);
                item.identifierOrCriteria = resolver.identifier;
            } else {
                ConsiderationItem memory item = consideration[resolver.index];
                item.itemType = convertCriteriaItemType(item.itemType);
                item.identifierOrCriteria = resolver.identifier;
            }
        }
    }

    function getSpentItems(
        OrderParameters memory parameters,
        uint256 numerator,
        uint256 denominator
    ) private view returns (SpentItem[] memory) {
        return
            getSpentItems(
                parameters.offer,
                parameters.startTime,
                parameters.endTime,
                numerator,
                denominator
            );
    }

    function getSpentItems(
        OrderParameters memory parameters
    ) private view returns (SpentItem[] memory) {
        return
            getSpentItems(
                parameters.offer,
                parameters.startTime,
                parameters.endTime
            );
    }

    function getSpentItems(
        OfferItem[] memory offerItems,
        uint256 startTime,
        uint256 endTime
    ) private view returns (SpentItem[] memory) {
        SpentItem[] memory spentItems = new SpentItem[](offerItems.length);
        for (uint256 i = 0; i < offerItems.length; i++) {
            spentItems[i] = getSpentItem(offerItems[i], startTime, endTime);
        }
        return spentItems;
    }

    function getSpentItems(
        OfferItem[] memory items,
        uint256 startTime,
        uint256 endTime,
        uint256 numerator,
        uint256 denominator
    ) private view returns (SpentItem[] memory) {
        SpentItem[] memory spentItems = new SpentItem[](items.length);
        for (uint256 i = 0; i < items.length; i++) {
            spentItems[i] = getSpentItem(
                items[i],
                startTime,
                endTime,
                numerator,
                denominator
            );
        }
        return spentItems;
    }

    function getSpentItem(
        OfferItem memory offerItem,
        uint256 startTime,
        uint256 endTime
    ) private view returns (SpentItem memory spent) {
        require(
            offerItem.itemType != ItemType.ERC721_WITH_CRITERIA &&
                offerItem.itemType != ItemType.ERC1155_WITH_CRITERIA,
            "Cannot convert a criteria  amount for criteria item type"
        );
        spent = SpentItem({
            itemType: offerItem.itemType,
            token: offerItem.token,
            identifier: offerItem.identifierOrCriteria,
            amount: _locateCurrentAmount({
                item: offerItem,
                startTime: startTime,
                endTime: endTime
            })
        });
    }

    function getSpentItem(
        OfferItem memory item,
        uint256 startTime,
        uint256 endTime,
        uint256 numerator,
        uint256 denominator
    ) private view returns (SpentItem memory spent) {
        require(
            item.itemType != ItemType.ERC721_WITH_CRITERIA &&
                item.itemType != ItemType.ERC1155_WITH_CRITERIA,
            "Cannot convert a criteria  amount for criteria item type"
        );
        spent = SpentItem({
            itemType: item.itemType,
            token: item.token,
            identifier: item.identifierOrCriteria,
            amount: _applyFraction({
                numerator: numerator,
                denominator: denominator,
                item: item,
                startTime: startTime,
                endTime: endTime
            })
        });
    }

    function getReceivedItems(
        OrderParameters memory parameters
    ) private view returns (ReceivedItem[] memory) {
        return
            getReceivedItems(
                parameters.consideration,
                parameters.startTime,
                parameters.endTime
            );
    }

    function getReceivedItems(
        OrderParameters memory parameters,
        uint256 numerator,
        uint256 denominator
    ) private view returns (ReceivedItem[] memory) {
        return
            getReceivedItems(
                parameters.consideration,
                parameters.startTime,
                parameters.endTime,
                numerator,
                denominator
            );
    }

    function getReceivedItems(
        ConsiderationItem[] memory considerationItems,
        uint256 startTime,
        uint256 endTime
    ) private view returns (ReceivedItem[] memory) {
        ReceivedItem[] memory receivedItems = new ReceivedItem[](
            considerationItems.length
        );
        for (uint256 i = 0; i < considerationItems.length; i++) {
            receivedItems[i] = getReceivedItem(
                considerationItems[i],
                startTime,
                endTime
            );
        }
        return receivedItems;
    }

    function getReceivedItems(
        ConsiderationItem[] memory considerationItems,
        uint256 startTime,
        uint256 endTime,
        uint256 numerator,
        uint256 denominator
    ) private view returns (ReceivedItem[] memory) {
        ReceivedItem[] memory receivedItems = new ReceivedItem[](
            considerationItems.length
        );
        for (uint256 i = 0; i < considerationItems.length; i++) {
            receivedItems[i] = getReceivedItem(
                considerationItems[i],
                startTime,
                endTime,
                numerator,
                denominator
            );
        }
        return receivedItems;
    }

    function getReceivedItem(
        ConsiderationItem memory considerationItem,
        uint256 startTime,
        uint256 endTime
    ) private view returns (ReceivedItem memory received) {
        require(
            considerationItem.itemType != ItemType.ERC721_WITH_CRITERIA &&
                considerationItem.itemType != ItemType.ERC1155_WITH_CRITERIA,
            "Cannot convert a criteria  amount for criteria item type"
        );
        received = ReceivedItem({
            itemType: considerationItem.itemType,
            token: considerationItem.token,
            identifier: considerationItem.identifierOrCriteria,
            amount: _locateCurrentAmount({
                item: considerationItem,
                startTime: startTime,
                endTime: endTime
            }),
            recipient: considerationItem.recipient
        });
    }

    function getReceivedItem(
        ConsiderationItem memory considerationItem,
        uint256 startTime,
        uint256 endTime,
        uint256 numerator,
        uint256 denominator
    ) private view returns (ReceivedItem memory received) {
        require(
            considerationItem.itemType != ItemType.ERC721_WITH_CRITERIA &&
                considerationItem.itemType != ItemType.ERC1155_WITH_CRITERIA,
            "Cannot convert a criteria  amount for criteria item type"
        );
        received = ReceivedItem({
            itemType: considerationItem.itemType,
            token: considerationItem.token,
            identifier: considerationItem.identifierOrCriteria,
            amount: _applyFraction({
                numerator: numerator,
                denominator: denominator,
                item: considerationItem,
                startTime: startTime,
                endTime: endTime
            }),
            recipient: considerationItem.recipient
        });
    }

    function _locateCurrentAmount(
        OfferItem memory item,
        uint256 startTime,
        uint256 endTime
    ) private view returns (uint256) {
        return
            _locateCurrentAmount({
                startAmount: item.startAmount,
                endAmount: item.endAmount,
                startTime: startTime,
                endTime: endTime,
                roundUp: false
            });
    }

    function _locateCurrentAmount(
        ConsiderationItem memory item,
        uint256 startTime,
        uint256 endTime
    ) private view returns (uint256) {
        return
            _locateCurrentAmount({
                startAmount: item.startAmount,
                endAmount: item.endAmount,
                startTime: startTime,
                endTime: endTime,
                roundUp: true
            });
    }

    function _applyFraction(
        uint256 numerator,
        uint256 denominator,
        uint256 startTime,
        uint256 endTime,
        OfferItem memory item
    ) private view returns (uint256) {
        uint256 startAmount = item.startAmount;
        uint256 endAmount = item.endAmount;
        return
            _applyFraction({
                numerator: numerator,
                denominator: denominator,
                startAmount: startAmount,
                endAmount: endAmount,
                startTime: startTime,
                endTime: endTime,
                roundUp: false // don't round up offers
            });
    }

    function _applyFraction(
        uint256 numerator,
        uint256 denominator,
        uint256 startTime,
        uint256 endTime,
        ConsiderationItem memory item
    ) private view returns (uint256) {
        uint256 startAmount = item.startAmount;
        uint256 endAmount = item.endAmount;

        return
            _applyFraction({
                numerator: numerator,
                denominator: denominator,
                startAmount: startAmount,
                endAmount: endAmount,
                startTime: startTime,
                endTime: endTime,
                roundUp: true // round up considerations
            });
    }
}
