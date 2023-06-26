// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import {DeploySeaport} from "script/DeploySeaport.s.sol";

contract InheritDeploySeaportTest is Test, DeploySeaport {
    function testDeploy() external {
        deployCanonicalConduitControllerAndSeaport();

        assertTrue(
            CANONICAL_SEAPORT_1_5_ADDRESS.code.length > 0,
            "Expected seaport code length to be non-zero"
        );
        assertTrue(
            CANONICAL_CONDUIT_CONTROLLER_ADDRESS.code.length > 0,
            "Expected conduit controller code length to be non-zero"
        );
    }
}
