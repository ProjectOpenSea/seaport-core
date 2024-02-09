// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

uint256 constant Rental_validateOrder_selector = 0x0064e1d4;

// Zone Parameters
uint256 constant Rental_ZoneParameters_orderHash_offset = 0x00;
uint256 constant Rental_ZoneParameters_fulfiller_offset = 0x20;
uint256 constant Rental_ZoneParameters_offerer_offset = 0x40;
uint256 constant Rental_ZoneParameters_offer_head_offset = 0x60;
uint256 constant Rental_ZoneParameters_consideration_head_offset = 0x80;
uint256 constant Rental_ZoneParameters_totalExecutions_head_offset = 0xa0;
uint256 constant Rental_ZoneParameters_extraData_head_offset = 0xc0;
uint256 constant Rental_ZoneParameters_orderHashes_head_offset = 0xe0;
uint256 constant Rental_ZoneParameters_startTime_offset = 0x100;
uint256 constant Rental_ZoneParameters_endTime_offset = 0x120;
uint256 constant Rental_ZoneParameters_zoneHash_offset = 0x140;
uint256 constant Rental_ZoneParameters_orderType_offset = 0x160;
uint256 constant Rental_ZoneParameters_base_tail_offset = 0x180;

// Order Parameters
uint256 constant Rental_OrderParameters_orderType_offset = 0x80;
