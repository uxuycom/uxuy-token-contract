# UXUY Token Contracts

Smart contracts for the UXUY token, as specified in the UXUY Whitepaper v3.0 (ch. 7 token utility, ch. 8 token economics & multi-chain issuance).

## Architecture

| Layer | Chain | Contract | Status |
| --- | --- | --- | --- |
| Canonical token | Ethereum | `UXUY.sol` — ERC20 + Permit + Burnable, 1B fixed supply, no owner | drafted, tested |
| Deployer | all chains | `UXUYDeployer.sol` — CREATE3 factory, salt namespaced by sender; same address everywhere | drafted, tested |
| Bridge | Ethereum | LayerZero OFT Adapter (locks canonical UXUY) | next |
| Bridge | BNB Chain, Base | LayerZero OFT (mapped UXUY, mint/burn only by LayerZero endpoint) | next |
| Vesting | Ethereum | Sablier Lockup Linear streams (investors, team & advisors, community, ecosystem) | proposed |
| Airdrop | Ethereum | Merkle distributor, 100% liquid on claim | proposed |
| Staking v1 | BNB Chain | stake / unstake with cooldown, tier read | proposed |

## Decisions (2026-11-03)

- Token includes `ERC20Burnable` (holder self-burn only). No `ERC20Votes`; governance power comes from the staking contract.
- Cross-chain uses LayerZero OFT on every chain. Base native bridge was considered and rejected for consistency.
- The token contract has no admin surface at all: no mint, no pause, no blacklist, no fee, no proxy. Every privileged function lives in peripheral contracts (bridge config, vesting cancel) behind a Safe multisig with a timelock, and is disclosed.

## Allocation at TGE (from whitepaper rev 253)

| Bucket | % | TGE unlock | Vesting |
| --- | --- | --- | --- |
| Community | 42 | 8 (airdrop season 1) | 34 over 36m linear |
| Investors | 20 | 0 | 12m cliff, then 24m linear |
| Team & Advisors | 18 | 0 | 12m cliff, then 48m linear |
| Ecosystem | 15 | 3 | 12 over 36m linear |
| Liquidity | 5 | 5 | — |

TGE float 16%.

## Same address on every chain + vanity address

`UXUYDeployer` is a CREATE3 factory. A CREATE3 address depends only on (factory address, caller, salt), not on the
bytecode or constructor args, so the Ethereum token and the future OFT contracts on BNB Chain and Base share one
address. The factory itself is deployed through the canonical CREATE2 deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C`
with the fixed `FACTORY_SALT`, which puts it at the same address on every chain.

Order of operations (each step pins an input of the next):

1. Freeze `UXUYDeployer.sol` + compiler settings and have it audited. Any later byte change moves the factory
   address and invalidates mined salts.
2. Pick the deployer EOA (hardware wallet, used for nothing else). Its address is part of the salt namespace.
   Protect this key for as long as any chain remains undeployed: whoever holds it can put any contract at
   UXUY's address on a chain we have not reached yet.
3. Mine the salt offline: `tools/vanity` (Go, ~9M candidates/s on an M3 Max; 8 hex chars ≈ 8 min, 9 ≈ 2 h,
   10 ≈ 1.5 days). Only the salt is searched, the key is never touched.
4. Verify with `DEPLOYER=… SALT=… forge script script/Predict.s.sol`.
5. Per chain: `script/DeployFactory.s.sol`, then `script/DeployUXUY.s.sol` (Ethereum) or the OFT script (later)
   from the same deployer EOA with the same salt.

## Audit

Scope, properties, trust assumptions and the verification commands are in [AUDIT.md](AUDIT.md).

## Development

```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge build
forge test
forge fmt --check
```

Mine and deploy:

```bash
# factory address (same on all chains)
forge script script/DeployFactory.s.sol --sig "expectedAddress()"
# explore: collect every address matching a known-nice pattern for 30 minutes, sorted by rarity
cd tools/vanity && go run . -factory <factory> -deployer <EOA> -explore 30m -minbits 27 > candidates.tsv
# or target one pattern
go run . -factory <factory> -deployer <EOA> -prefix 0000 -suffix EEEE -checksum
# check
DEPLOYER=<EOA> SALT=<salt> forge script script/Predict.s.sol
# deploy (Ethereum)
forge script script/DeployFactory.s.sol --rpc-url $ETH_RPC --broadcast --verify
RECIPIENT=<TGE Safe> SALT=<salt> forge script script/DeployUXUY.s.sol --rpc-url $ETH_RPC --broadcast --verify
```

Toolchain: Foundry, Solidity 0.8.28, OpenZeppelin Contracts v5.4.0, Solady v0.1.26 (CREATE3 only), Go 1.22+ for the miner. Audits planned: SlowMist and CertiK before TGE.
