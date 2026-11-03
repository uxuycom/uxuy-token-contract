// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {UXUYDeployer} from "../src/UXUYDeployer.sol";
import {CREATE2_DEPLOYER, FACTORY_SALT} from "../src/Constants.sol";

/// @notice Deploys UXUYDeployer at the same address on every chain. Run once per chain, any funded key.
///   forge script script/DeployFactory.s.sol --rpc-url $RPC --broadcast --verify
contract DeployFactory is Script {
    function expectedAddress() public pure returns (address) {
        return vm.computeCreate2Address(FACTORY_SALT, keccak256(type(UXUYDeployer).creationCode), CREATE2_DEPLOYER);
    }

    function run() external returns (UXUYDeployer factory) {
        address expected = expectedAddress();
        if (expected.code.length > 0) {
            console.log("UXUYDeployer already at", expected);
            return UXUYDeployer(expected);
        }
        vm.startBroadcast();
        factory = new UXUYDeployer{salt: FACTORY_SALT}();
        vm.stopBroadcast();
        require(address(factory) == expected, "factory address mismatch");
        console.log("UXUYDeployer deployed at", address(factory));
    }
}
