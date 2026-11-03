// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title UXUY Token
/// @notice Fixed-supply ERC-20 with EIP-2612 permit. The full supply is minted once at deployment.
///         No owner, no minting, no pausing, no blacklist, no fees, not upgradeable.
contract UXUY is ERC20, ERC20Burnable, ERC20Permit {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;

    error ZeroAddress();

    /// @param recipient Receives the entire supply.
    constructor(address recipient) ERC20("UXUY", "UXUY") ERC20Permit("UXUY") {
        if (recipient == address(0)) revert ZeroAddress();
        _mint(recipient, TOTAL_SUPPLY);
    }
}
