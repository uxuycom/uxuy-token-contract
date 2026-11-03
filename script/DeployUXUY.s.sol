// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {UXUY} from "../src/UXUY.sol";
import {UXUYDeployer} from "../src/UXUYDeployer.sol";
import {DeployFactory} from "./DeployFactory.s.sol";

/// @notice Deploys the canonical UXUY token on Ethereum through UXUYDeployer (CREATE3).
/// @dev Env:
///   RECIPIENT  TGE distribution Safe that receives the whole supply (must be a contract)
///   SALT       mined vanity salt (bytes32). The broadcasting key must be the one the salt was mined for.
///   forge script script/DeployUXUY.s.sol --rpc-url $ETH_RPC --broadcast --verify
contract DeployUXUY is Script {
    function run() external returns (UXUY token) {
        address recipient = vm.envAddress("RECIPIENT");
        bytes32 salt = vm.envBytes32("SALT");
        require(recipient.code.length > 0, "RECIPIENT must be a contract (Safe)");

        UXUYDeployer factory = UXUYDeployer(new DeployFactory().expectedAddress());
        require(address(factory).code.length > 0, "deploy factory first");

        (, address sender,) = vm.readCallers();
        address expected = factory.predict(sender, salt);
        console.log("Deployer EOA     ", sender);
        console.log("Expected address ", expected);
        require(expected.code.length == 0, "address already used");

        bytes memory initCode = abi.encodePacked(type(UXUY).creationCode, abi.encode(recipient));

        vm.startBroadcast();
        token = UXUY(factory.deploy(salt, initCode));
        vm.stopBroadcast();

        require(address(token) == expected, "address mismatch");
        require(token.balanceOf(recipient) == token.TOTAL_SUPPLY(), "supply not at recipient");
        console.log("UXUY deployed at ", address(token));
    }
}
