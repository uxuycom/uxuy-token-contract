// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {UXUY} from "../src/UXUY.sol";

contract UXUYTest is Test {
    UXUY internal token;

    address internal treasury = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant SUPPLY = 1_000_000_000e18;

    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        token = new UXUY(treasury);
    }

    // ---------------------------------------------------------------- deployment

    function test_Metadata() public view {
        assertEq(token.name(), "UXUY");
        assertEq(token.symbol(), "UXUY");
        assertEq(token.decimals(), 18);
    }

    function test_SupplyMintedOnceToRecipient() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(treasury), SUPPLY);
    }

    function test_RevertWhen_RecipientIsZero() public {
        vm.expectRevert(UXUY.ZeroAddress.selector);
        new UXUY(address(0));
    }

    /// No mint / owner / pause / blacklist entry points exist. Calling the usual selectors must hit the
    /// fallback-less contract and revert.
    function test_NoAdminSelectors() public {
        bytes4[6] memory sels = [
            bytes4(keccak256("mint(address,uint256)")),
            bytes4(keccak256("owner()")),
            bytes4(keccak256("pause()")),
            bytes4(keccak256("unpause()")),
            bytes4(keccak256("blacklist(address)")),
            bytes4(keccak256("setFee(uint256)"))
        ];
        for (uint256 i; i < sels.length; ++i) {
            (bool ok,) = address(token).call(abi.encodeWithSelector(sels[i], alice, 1));
            assertFalse(ok, "unexpected admin selector");
        }
    }

    // ---------------------------------------------------------------- transfers

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(treasury);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(treasury), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhen_TransferExceedsBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_TransferFromRespectsAllowance() public {
        vm.prank(treasury);
        token.approve(alice, 100e18);

        vm.prank(alice);
        token.transferFrom(treasury, bob, 60e18);
        assertEq(token.balanceOf(bob), 60e18);
        assertEq(token.allowance(treasury, alice), 40e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 40e18, 41e18));
        token.transferFrom(treasury, bob, 41e18);
    }

    // ---------------------------------------------------------------- burn

    function testFuzz_BurnReducesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(treasury);
        token.burn(amount);
        assertEq(token.totalSupply(), SUPPLY - amount);
        assertEq(token.balanceOf(treasury), SUPPLY - amount);
    }

    function test_BurnFromRequiresAllowance() public {
        vm.prank(treasury);
        token.approve(alice, 10e18);

        vm.prank(alice);
        token.burnFrom(treasury, 10e18);
        assertEq(token.totalSupply(), SUPPLY - 10e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.burnFrom(treasury, 1);
    }

    function test_RevertWhen_BurnExceedsBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.burn(1);
    }

    // ---------------------------------------------------------------- permit (EIP-2612)

    function test_Permit() public {
        (address owner, uint256 pk) = makeAddrAndKey("owner");
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(pk, owner, bob, 5e18, 0, deadline);

        token.permit(owner, bob, 5e18, deadline, v, r, s);
        assertEq(token.allowance(owner, bob), 5e18);
        assertEq(token.nonces(owner), 1);

        // replay must fail
        vm.expectRevert();
        token.permit(owner, bob, 5e18, deadline, v, r, s);
    }

    function test_RevertWhen_PermitExpired() public {
        (address owner, uint256 pk) = makeAddrAndKey("owner");
        uint256 deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(pk, owner, bob, 1, 0, deadline);
        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        token.permit(owner, bob, 1, deadline, v, r, s);
    }

    function test_RevertWhen_PermitWrongSigner() public {
        (address owner,) = makeAddrAndKey("owner");
        (, uint256 malloryPk) = makeAddrAndKey("mallory");
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(malloryPk, owner, bob, 1, 0, deadline);
        vm.expectRevert();
        token.permit(owner, bob, 1, deadline, v, r, s);
    }

    function _signPermit(uint256 pk, address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(pk, digest);
    }
}
