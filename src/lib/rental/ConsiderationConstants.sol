// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Adding a stub contract to satisfy foundry expecting there
// to be a contract in this file when using deploy scripts
contract ConsiderationConstants {}

uint256 constant Rental_validateOrder_selector = 0x827b45fa;

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
uint256 constant Rental_ZoneParameters_base_tail_offset = 0x160;
