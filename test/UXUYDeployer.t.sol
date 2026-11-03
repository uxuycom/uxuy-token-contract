// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {UXUY} from "../src/UXUY.sol";
import {UXUYDeployer} from "../src/UXUYDeployer.sol";
import {CREATE2_DEPLOYER, FACTORY_SALT} from "../src/Constants.sol";

contract Other {
    uint256 public immutable x;

    constructor(uint256 _x) {
        x = _x;
    }
}

contract UXUYDeployerTest is Test {
    UXUYDeployer internal factory;
    address internal deployer = makeAddr("deployer");
    address internal attacker = makeAddr("attacker");
    address internal safe = makeAddr("safe");
    bytes32 internal salt = keccak256("some mined salt");

    function setUp() public {
        // Mirror production: factory itself comes out of the canonical CREATE2 deployer. Forge pre-deploys it;
        // etch the real runtime code if a future forge version stops doing so.
        if (CREATE2_DEPLOYER.code.length == 0) {
            vm.etch(
                CREATE2_DEPLOYER,
                abi.encodePacked(
                    hex"7f",
                    bytes32(type(uint256).max - 0x1f),
                    hex"3601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"
                )
            );
        }
        (bool ok, bytes memory ret) =
            CREATE2_DEPLOYER.call(abi.encodePacked(FACTORY_SALT, type(UXUYDeployer).creationCode));
        require(ok, "factory deploy failed");
        factory = UXUYDeployer(address(bytes20(ret)));
        assertEq(
            address(factory),
            vm.computeCreate2Address(FACTORY_SALT, keccak256(type(UXUYDeployer).creationCode), CREATE2_DEPLOYER)
        );
    }

    function _uxuyInit(address recipient) internal pure returns (bytes memory) {
        return abi.encodePacked(type(UXUY).creationCode, abi.encode(recipient));
    }

    function test_DeployMatchesPredict() public {
        address predicted = factory.predict(deployer, salt);
        vm.prank(deployer);
        address got = factory.deploy(salt, _uxuyInit(safe));
        assertEq(got, predicted);
        assertEq(UXUY(got).balanceOf(safe), 1_000_000_000e18);
    }

    /// Same deployer + salt gives the same address whatever the bytecode or constructor args are.
    /// This is what lets the OFT on BNB Chain / Base share the Ethereum token's address.
    function test_AddressIndependentOfBytecode() public {
        address predicted = factory.predict(deployer, salt);

        uint256 snap = vm.snapshotState();
        vm.prank(deployer);
        address a = factory.deploy(salt, _uxuyInit(safe));
        vm.revertToState(snap);

        vm.prank(deployer);
        address b = factory.deploy(salt, abi.encodePacked(type(Other).creationCode, abi.encode(uint256(42))));

        assertEq(a, predicted);
        assertEq(b, predicted);
        assertEq(Other(b).x(), 42);
    }

    function test_AddressIndependentOfConstructorArgs() public view {
        // predict() takes no initcode at all; nothing about the recipient can leak into the address.
        assertEq(factory.predict(deployer, salt), factory.predict(deployer, salt));
    }

    /// Front-running protection: a different sender with the same public salt lands elsewhere.
    function test_SaltNamespacedBySender() public {
        address ours = factory.predict(deployer, salt);
        address theirs = factory.predict(attacker, salt);
        assertTrue(ours != theirs);

        vm.prank(attacker);
        address got = factory.deploy(salt, _uxuyInit(attacker));
        assertEq(got, theirs);
        assertEq(ours.code.length, 0, "our address must stay free");
    }

    function test_RevertWhen_SaltReused() public {
        vm.prank(deployer);
        factory.deploy(salt, _uxuyInit(safe));
        vm.prank(deployer);
        vm.expectRevert(CREATE3.DeploymentFailed.selector);
        factory.deploy(salt, _uxuyInit(safe));
    }

    function test_RevertWhen_ConstructorReverts() public {
        vm.prank(deployer);
        vm.expectRevert(CREATE3.DeploymentFailed.selector);
        factory.deploy(salt, _uxuyInit(address(0)));
    }

    function test_EmitsDeployed() public {
        address predicted = factory.predict(deployer, salt);
        vm.expectEmit(true, true, true, true, address(factory));
        emit UXUYDeployer.Deployed(deployer, salt, predicted);
        vm.prank(deployer);
        factory.deploy(salt, _uxuyInit(safe));
    }

    /// Reference formula the Go vanity miner (tools/vanity) implements. Must equal Solady's prediction.
    function testFuzz_ManualFormulaMatchesSolady(address d, bytes32 s) public view {
        bytes32 ns = keccak256(abi.encodePacked(d, s));
        address proxy = address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), ns, CREATE3.PROXY_INITCODE_HASH)))
            )
        );
        address manual =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), proxy, bytes1(0x01))))));
        assertEq(manual, factory.predict(d, s));
    }
}
