// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {UXUY} from "../src/UXUY.sol";
import {UXUYDeployer} from "../src/UXUYDeployer.sol";
import {CREATE2_DEPLOYER, FACTORY_SALT} from "../src/Constants.sol";

/// Guards that must keep passing from audit freeze until mainnet deployment.
contract FreezeTest is Test {
    /// The factory address is an input to vanity-salt mining. If this test fails, every mined salt is void:
    /// the factory bytecode or compiler settings changed after the freeze.
    function test_FactoryAddressFrozen() public pure {
        address expected =
            vm.computeCreate2Address(FACTORY_SALT, keccak256(type(UXUYDeployer).creationCode), CREATE2_DEPLOYER);
        assertEq(expected, 0x9903b22C5150191289c67De8a9Ea195EdAEE61B7, "factory bytecode changed; re-mine salts");
    }

    /// Token runtime code contains no DELEGATECALL / CALLCODE / SELFDESTRUCT / CREATE opcodes, and
    /// no external CALL at all: nothing in it can reach another contract or change its own code.
    function test_TokenBytecodeHasNoDangerousOpcodes() public {
        UXUY token = new UXUY(address(0xBEEF));
        bytes memory code = address(token).code;
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f; // skip PUSH data
                continue;
            }
            assertTrue(op != 0xf0, "CREATE");
            assertTrue(op != 0xf1, "CALL");
            assertTrue(op != 0xf2, "CALLCODE");
            assertTrue(op != 0xf4, "DELEGATECALL");
            assertTrue(op != 0xf5, "CREATE2");
            assertTrue(op != 0xff, "SELFDESTRUCT");
        }
    }

    /// Factory runtime code: CREATE2 and CALL are expected (that is CREATE3), nothing else that moves code or ETH out.
    function test_FactoryBytecodeHasNoUpgradeOpcodes() public {
        UXUYDeployer f = new UXUYDeployer();
        bytes memory code = address(f).code;
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf2, "CALLCODE");
            assertTrue(op != 0xf4, "DELEGATECALL");
            assertTrue(op != 0xff, "SELFDESTRUCT");
        }
    }

    /// The token has no owner slot, no paused flag, no fee variable. Constructor-time storage writes are exactly
    /// the four OpenZeppelin ERC-20 fields: _name, _symbol, _totalSupply, _balances[recipient].
    function test_TokenConstructorWritesOnlyERC20Fields() public {
        vm.record();
        UXUY token = new UXUY(address(0xBEEF));
        (, bytes32[] memory writes) = vm.accesses(address(token));
        assertEq(writes.length, 4, "unexpected storage writes in constructor");
    }
}
