# Audit package — UXUY token and deployer

Prepared 2026-11-03 for SlowMist and CertiK. Scope is two contracts; everything else (vesting, airdrop,
LayerZero OFT, staking) is out of scope for this round and will be submitted separately.

## Scope

| File | Lines | Purpose |
| --- | --- | --- |
| `src/UXUY.sol` | ~25 | Canonical UXUY ERC-20 on Ethereum |
| `src/UXUYDeployer.sol` | ~35 | CREATE3 factory giving identical addresses on every chain |
| `src/Constants.sol` | ~10 | CREATE2 deployer address and factory salt |

Dependencies (unmodified, pinned):

| Library | Version | Used for |
| --- | --- | --- |
| OpenZeppelin Contracts | v5.4.0 | ERC20, ERC20Burnable, ERC20Permit |
| Solady | v0.1.26 | `CREATE3` library only |

Compiler: solc 0.8.28, EVM `cancun`, optimizer on, 1,000,000 runs, `via_ir` off, metadata hash stripped
(`bytecode_hash = "none"`, `cbor_metadata = false`). Settings are in `foundry.toml` and must not change after the
freeze: the factory address, and therefore every mined vanity salt, depends on the exact bytecode.

## Intended properties

UXUY token:

1. Total supply is 1,000,000,000 × 10^18, minted once in the constructor to `recipient`. No code path can mint again.
2. Supply only decreases, and only through `burn` / `burnFrom` by a holder or their approved spender.
3. No owner, no roles, no pause, no blacklist, no transfer fee, no hooks, no external calls, no upgradeability.
4. EIP-2612 `permit` with standard domain separator (name "UXUY", version "1").
5. Runtime code contains no CALL, DELEGATECALL, CALLCODE, CREATE, CREATE2 or SELFDESTRUCT opcode.

UXUYDeployer:

6. `deploy(salt, initCode)` lands at `predict(msg.sender, salt)` regardless of `initCode`.
7. Two different callers with the same salt never collide; nobody can occupy another caller's predicted address.
8. A (caller, salt) pair can be used once per chain. A reverting constructor leaves the address free.
9. The factory holds no state and no funds; `msg.value` is forwarded to the deployed contract.
10. Deployed through the canonical CREATE2 deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C` with
    `keccak256("UXUYDeployer.v1")`, the factory's address is `0x9903b22C5150191289c67De8a9Ea195EdAEE61B7` on
    every chain. `test/Freeze.t.sol` pins this.

## Design notes (kept out of the source on purpose)

- Token: the TGE distribution Safe is the `recipient`; it forwards tokens to liquidity, treasury and vesting in
  the same block. Mapped tokens on other chains will be minted by a bridge contract, never by this contract.
- Factory: the salt is namespaced with `msg.sender` so that nobody can claim UXUY's address on a chain we have
  not deployed to yet by replaying our public salt. The factory is immutable, permissionless and stateless.
- Changing one byte of `UXUYDeployer` or its compiler settings moves the factory address and voids mined salts.

## Trust assumptions and known limitations

- The deployer EOA that mines and uses the vanity salt can, on any chain where that salt has not been consumed
  yet, deploy arbitrary code at UXUY's address. Operational control: hardware wallet, single purpose, and
  deploy on every planned chain as early as possible. This is inherent to any cross-chain same-address scheme.
- The factory is permissionless by design. Anyone may use it for their own deployments; this does not affect UXUY.
- `UXUY.recipient` is expected to be a Safe multisig. The deploy script refuses an EOA, the contract does not.
- Tokens sent to the token contract address itself are unrecoverable (standard ERC-20 behaviour, no rescue
  function on purpose, to keep zero admin surface).
- No reentrancy surface: the token makes no external calls; the factory's only call is to the CREATE3 proxy it
  just created.

## Verification

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge build
forge test              # 26 tests: unit, fuzz (1024 runs), invariant (256 runs × 64 depth), freeze guards
forge coverage          # src/: 100% lines, statements, branches, functions
forge fmt --check
slither . --filter-paths "lib/|script/|test/"   # 0 results across 100 detectors (slither 0.11.4)
```

Test map:

| Property | Test |
| --- | --- |
| 1, 2 | `UXUY.t.sol`, `UXUY.invariant.t.sol` |
| 3 | `UXUY.t.sol::test_NoAdminSelectors`, `Freeze.t.sol::test_TokenConstructorWritesOnlyERC20Fields` |
| 4 | `UXUY.t.sol::test_Permit*` |
| 5 | `Freeze.t.sol::test_TokenBytecodeHasNoDangerousOpcodes` |
| 6, 7, 8 | `UXUYDeployer.t.sol` |
| 10 | `Freeze.t.sol::test_FactoryAddressFrozen` |

## Deployment procedure (post-audit)

1. Tag the audited commit. Rebuild from clean and confirm `forge test` + `test_FactoryAddressFrozen` pass.
2. Choose the deployer EOA. Mine the vanity salt with `tools/vanity` against factory
   `0x9903b22C5150191289c67De8a9Ea195EdAEE61B7` and that EOA. Confirm with `script/Predict.s.sol`.
3. Ethereum: `script/DeployFactory.s.sol`, then `script/DeployUXUY.s.sol` with `RECIPIENT` = TGE Safe, `SALT` = mined salt.
   Verify source on Etherscan. Confirm `totalSupply()` and `balanceOf(RECIPIENT)` equal 1e27.
4. Publish token and factory addresses on docs.uxuy.com. Repeat step 3's factory deployment on BNB Chain and
   Base when the OFT contracts are ready, from the same EOA with the same salt.
