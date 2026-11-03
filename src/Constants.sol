// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Canonical CREATE2 deployer, present at this address on Ethereum, BNB Chain and Base.
address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

/// @dev Salt for deploying UXUYDeployer through CREATE2_DEPLOYER.
bytes32 constant FACTORY_SALT = keccak256("UXUYDeployer.v1");
