// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {DeployFactory} from "./DeployFactory.s.sol";

/// @notice Offline check of a mined salt: prints the factory address and the token address for DEPLOYER + SALT.
///   DEPLOYER=0x... SALT=0x... forge script script/Predict.s.sol
contract Predict is Script {
    function run() external {
        address factory = new DeployFactory().expectedAddress();
        address deployer = vm.envAddress("DEPLOYER");
        bytes32 salt = vm.envBytes32("SALT");
        address predicted = CREATE3.predictDeterministicAddress(keccak256(abi.encodePacked(deployer, salt)), factory);
        console.log("Factory  ", factory);
        console.log("Deployer ", deployer);
        console.log("Predicted", predicted);
    }
}
