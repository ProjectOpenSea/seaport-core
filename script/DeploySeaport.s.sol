// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {Script, console2} from "forge-std/Script.sol";
import {BaseCreate2Script} from "create2-helpers/script/BaseCreate2Script.s.sol";
import {
    SEAPORT_1_5_INITCODE, CONDUIT_CONTROLLER_INITCODE
} from "./Constants.sol";

contract DeploySeaport is BaseCreate2Script {
    bytes32 constant CONDUIT_CONTROLLER_SALT =
        0x0000000000000000000000000000000000000000dc0ef3c79297660496040000;
    bytes32 constant SEAPORT_SALT =
        0x0000000000000000000000000000000000000000d4b6fcc21169b803f25d2210;

    address constant CANONICAL_CONDUIT_CONTROLLER_ADDRESS =
        0x00000000F9490004C11Cef243f5400493c00Ad63;
    address constant CANONICAL_SEAPORT_1_5_ADDRESS =
        0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC;

    function run() public {
        setUp();

        string[] memory networks;
        try vm.envString("NETWORKS", ",") returns (string[] memory _networks) {
            networks = _networks;
        } catch {
            console2.log("No networks specified, defaulting to anvil");
            networks = new string[](1);
            networks[0] = "anvil";
        }
        runOnNetworks(this.deployCanonicalConduitControllerAndSeaport, networks);
    }

    function deployConduitController(address _deployer)
        public
        returns (address)
    {
        return _immutableCreate2IfNotDeployed(
            _deployer, CONDUIT_CONTROLLER_SALT, CONDUIT_CONTROLLER_INITCODE
        );
    }

    function deploySeaport(address _deployer) public returns (address) {
        return _immutableCreate2IfNotDeployed(
            _deployer, SEAPORT_SALT, SEAPORT_1_5_INITCODE
        );
    }

    function deployCanonicalConduitControllerAndSeaport()
        public
        returns (address)
    {
        return deployCanonicalConduitControllerAndSeaportWithDeployer(deployer);
    }

    function deployCanonicalConduitControllerAndSeaportWithDeployer(
        address _deployer
    ) public returns (address) {
        console2.log("Deploying ConduitController and Seaport");

        require(
            deployConduitController(_deployer)
                == CANONICAL_CONDUIT_CONTROLLER_ADDRESS,
            "Deployed ConduitController address does not match expected address"
        );

        require(
            deploySeaport(_deployer) == CANONICAL_SEAPORT_1_5_ADDRESS,
            "Deployed Seaport address does not match expected address"
        );
        return CANONICAL_SEAPORT_1_5_ADDRESS;
    }
}
