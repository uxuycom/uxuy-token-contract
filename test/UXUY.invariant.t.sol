// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {UXUY} from "../src/UXUY.sol";

/// Random transfers / burns among a fixed actor set. Supply can only go down by exactly what was burned,
/// and the sum of balances always equals totalSupply.
contract UXUYHandler is Test {
    UXUY public token;
    address[] public actors;
    uint256 public burned;

    constructor(UXUY _token, address treasury) {
        token = _token;
        actors.push(treasury);
        for (uint256 i; i < 4; ++i) {
            actors.push(makeAddr(string(abi.encodePacked("actor", i))));
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function burn(uint256 fromSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        token.burn(amount);
        burned += amount;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}

contract UXUYInvariantTest is Test {
    UXUY internal token;
    UXUYHandler internal handler;
    address internal treasury = makeAddr("treasury");

    function setUp() public {
        token = new UXUY(treasury);
        handler = new UXUYHandler(token, treasury);
        targetContract(address(handler));
    }

    function invariant_SupplyEqualsInitialMinusBurned() public view {
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY() - handler.burned());
    }

    function invariant_BalancesSumToSupply() public view {
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, token.totalSupply());
    }

    function invariant_SupplyNeverExceedsCap() public view {
        assertLe(token.totalSupply(), token.TOTAL_SUPPLY());
    }
}
