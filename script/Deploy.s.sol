// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console2} from "forge-std/Script.sol";
import {BaseCreate2Script} from "create2-helpers/script/BaseCreate2Script.s.sol";

contract Deploy is BaseCreate2Script {
    bytes32 immutable CONDUIT_CONTROLLER_SALT =
        0x0000000000000000000000000000000000000000dc0ef3c79297660496040000;
    bytes32 immutable SEAPORT_SALT =
        0x0000000000000000000000000000000000000000d4b6fcc21169b803f25d2210;

    address immutable EXPECTED_CONDUIT_CONTROLLER_ADDRESS =
        0x00000000F9490004C11Cef243f5400493c00Ad63;
    address immutable EXPECTED_SEAPORT_1_5_ADDRESS =
        0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC;

    function run() public {
        // bytes memory conduitCreationCode = vm.getCode("out_deploy/Conduit.sol");
        // require(
        //     _create2IfNotDeployed(
        //         CONDUIT_CONTROLLER_SALT,
        //         conduitCreationCode
        //     ) == EXPECTED_CONDUIT_CONTROLLER_ADDRESS,
        //     "Deployed ConduitController address does not match expected address"
        // );
        // bytes memory seaportInitCode = abi.encode(
        //     vm.getCode("out_deploy/Seaport.sol"),
        //     abi.encodePacked(
        //         uint256(uint160(EXPECTED_CONDUIT_CONTROLLER_ADDRESS))
        //     )
        // );
        // require(
        //     _create2IfNotDeployed(SEAPORT_SALT, seaportInitCode) ==
        //         EXPECTED_SEAPORT_1_5_ADDRESS,
        //     "Deployed Seaport address does not match expected address"
        // );
    }
}
