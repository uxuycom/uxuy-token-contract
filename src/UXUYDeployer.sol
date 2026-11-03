// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CREATE3} from "solady/utils/CREATE3.sol";

/// @title UXUY Deployer
/// @notice CREATE3 factory. The deployed address depends only on this factory, the caller and the salt,
///         not on the bytecode, so the same caller and salt give the same address on every chain.
contract UXUYDeployer {
    event Deployed(address indexed deployer, bytes32 indexed salt, address indexed deployed);

    /// @notice Deploys `initCode` at `predict(msg.sender, salt)`. Reverts if that address is taken.
    /// @param salt Caller-chosen salt.
    /// @param initCode Creation code including constructor arguments.
    function deploy(bytes32 salt, bytes calldata initCode) external payable returns (address deployed) {
        deployed = CREATE3.deployDeterministic(msg.value, initCode, _namespaced(msg.sender, salt));
        emit Deployed(msg.sender, salt, deployed);
    }

    /// @notice Address `deployer` gets for `salt`.
    function predict(address deployer, bytes32 salt) external view returns (address) {
        return CREATE3.predictDeterministicAddress(_namespaced(deployer, salt));
    }

    function _namespaced(address deployer, bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(deployer, salt));
    }
}
