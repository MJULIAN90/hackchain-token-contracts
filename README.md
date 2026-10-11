# Hackchain HACK Token — Smart Contracts

Modular implementation of the $HACK tokenomics mechanisms.

> **Single source of truth.** This README is the current, authoritative description of the
> repository. Last verified against the code on 2026-10-11.

## Architecture

Token logic is split into independent contracts for security, auditability and scalability,
instead of one monolithic contract.

| File | Contract | Mechanisms covered |
|---|---|---|
| `HackTokenERC20.sol` | `HackToken` | Base ERC20 (roles: MINTER, BURNER, PAUSER) |
| `PresaleAllocation.sol` | `PresaleAllocation` | Presale allocation ledger with escrow-prefunded claims |
| `IncentivesPool.sol` | `IncentivesPool` | Central treasury for all reward distributions |
| `StakingContract.sol` | `StakingContract` | 1, 6 |
| `ReferralSystem.sol` | `ReferralSystem` | 2 |
| `MembershipSystem.sol` | `MembershipSystem` | 3, 13 |
| `PenaltySystem.sol` | `PenaltySystem` | 7, 9, 14, 25, 26, 30 |
| `ReputationBunises.sol` | `ReputationBonuses` | 15, 16, 17 |
| `EventRewards.sol` | `EventRewards` | 5, 10, 18, 19 |
| `EducatorBonuses.sol` | `EducatorBonuses` | 20, 21, 22, 24 |
| `RecruiterBonuses.sol` | `RecruiterBonuses` | 27, 28, 29 |
| `TalentBonuses.sol` | `TalentBonuses` | 4, 11, 23 |
| `ComissionSystem.sol` | `CommissionSystem` | 8 |

> Two filenames are misspelled on disk — `ReputationBunises.sol` and `ComissionSystem.sol` — and do
> not match the contract names inside them. Renaming them is safe but touches every import, so it
> is left as a separate change. The table above lists what is actually on disk.

## Access control

All reward/penalty contracts use OpenZeppelin AccessControl. Roles are granted to contracts rather
than external wallets wherever possible, to minimize trust assumptions.

## Build and test

```bash
forge build
forge test
forge test --gas-report
```

`foundry.toml` sets `via_ir = true`, so every build goes through the IR pipeline.

**Before deploying, pin `evm_version` in `foundry.toml`.** It is currently unset, which means the
compiler picks the newest version its toolchain supports (`cancun` for solc 0.8.24). That is fine
for Polygon PoS, but leaving it unset makes the bytecode depend on whoever compiles it — so source
verification on the block explorer, and the external audit, can fail to reproduce it.

```toml
evm_version = "paris"   # most conservative: avoids PUSH0 entirely
```

## Presale

`PresaleAllocation.sol` is the dedicated presale module. The sale itself happens off-chain; this
contract is the on-chain distribution ledger.

**Roles**

- The constructor takes the presale multisig address (`admin_`) directly and grants it
  `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE` and `PAUSER_ROLE` at deploy time. The deployer never holds any
  role on this contract, so there is nothing to revoke afterwards.
- `ADMIN_ROLE` is deliberately separate from `DEFAULT_ADMIN_ROLE`: the first operates the presale,
  the second grants and revokes roles. Keeping them apart means the operating multisig can later be
  rotated from a cold governance key without being able to mint new administrators itself.
- `PAUSER_ROLE` is separate for the same reason — pausing must be fast, and that key should not be
  able to move funds.

**Funding**

- `PRESALE_CAP` must be minted to the presale contract **after deployment**, by someone holding
  `MINTER_ROLE` on the token. This is a separate manual step; the deploy script does not do it.
  Until it happens, allocations can be written but no claim can be paid.

**Allocation and claiming**

- Admins assign allocations with `allocate()` or `allocateBatch()`. Allocations are **cumulative**:
  a buyer who purchases twice gets both amounts added.
- `allocateBatch()` may be called any number of times, across separate transactions and separate
  days, until `finalizePresale()`. The contract imposes no maximum batch size — gas is the only
  limit. Use **100–200 addresses per batch** (~3–6M gas against Polygon's ~30M block limit). An
  oversized batch reverts in full, writing nothing, so that failure mode is safe.
- **There is no idempotency guard.** Because allocations are cumulative, the contract cannot tell a
  mistaken resend from a genuine second purchase: resending a batch that already landed doubles
  every address in it. `beneficiaryCount` will not catch this (those addresses already existed) and
  `presaleCap` only catches it if the excess crosses 100M. **Reconcile `totalAllocated` against the
  backend's expected running total after every batch**, and if a transaction's outcome is unclear,
  read `allocations(address)` for one address in that batch before resending anything.
- Buyers claim vested tranches with `claim()`. Double-claiming is impossible.
- One-month cliff, then three monthly tranches of **33% / 33% / 34%** — the final tranche pays the
  exact remainder, so integer-division dust is never stranded.
- `finalizePresale()` freezes new allocations without blocking claims, and starts the schedule.
- `setAllocationListHash()` records, write-once, the hash of the delivery list the multisig
  approved, so the published buyer registry can be audited against the chain.
- `vestingStatus(address)` returns a beneficiary's allocated/claimed/vested/claimable amounts and
  the claim deadline in a single read, for the backend.

**Deadline and treasury**

- Buyers have `CLAIM_DEADLINE` (180 days after the close) to claim, **plus any time the contract
  spent paused in that window**. Repeated pauses accumulate. `claimDeadline()` and `pausedTime()`
  expose both, and reflect an in-progress pause immediately, not only once it is lifted.
- Past the deadline `claim()` closes permanently and `sweepUnclaimed()` sends whatever is left to
  the treasury, once.
- After finalization, `withdrawUnallocated()` returns only the unsold portion of the cap, once.
- `pause()`/`unpause()` freeze `allocate`, `allocateBatch`, `claim` and `finalizePresale()`.
  `withdrawUnallocated()` and `sweepUnclaimed()` stay usable while paused.

**By team decision** there is no per-address cap and no rescue function: a foreign token sent here
by mistake cannot be recovered. HACK sent here by mistake is collected by `sweepUnclaimed()` after
the deadline.

## Deployment

The HACK token is deployed separately, outside this stack.

| Script | Use |
|---|---|
| `script/DeployPresale.s.sol` | **The script to use for the presale.** Deploys only `PresaleAllocation`, against the token address you pass in. |
| `script/PresaleOps.s.sol` | Allocations, list hash, finalization, treasury sends. |
| `script/cargar-lote.sh` | Sends one allocation batch **and verifies it on chain**. Use this rather than calling `allocateBatch` by hand. |
| `script/DeployCore.s.sol` | Deploys the full stack **including a brand new `HackToken`**. |

> **Do not use `DeployCore.s.sol` for the presale.** Now that the token is deployed on its own, that
> script would leave the presale pointing at a token nobody else uses. It also currently fails
> `forge coverage` with a `Stack too deep` error (run coverage with `--ir-minimum` to work around
> it). Whoever owns the full-stack deployment should review that script.

Environment variables used by `DeployPresale.s.sol`:

- `HACK_TOKEN_ADDRESS` — the already-deployed HACK token
- `PRESALE_ADMIN_ADDRESS` — the multisig that administers the presale
- `PRESALE_CAP` — in units of 18 decimals (100,000,000 HACK is `1e26`)

`DeployCore.s.sol` additionally uses `TREASURY_ADDRESS`, `PROTOCOL_ADMIN_ADDRESS` and
`INITIAL_REWARD_POOL_FUNDING`.

For deployment keys, use an encrypted keystore or a hardware wallet. Do not keep raw private keys
in `.env`.

```bash
cast wallet import deployer --interactive
```

Example flow on Polygon Amoy:

```bash
# 1. Deploy the presale against the already-deployed token
forge script script/DeployPresale.s.sol:DeployPresale \
  --rpc-url $AMOY_RPC_URL \
  --account deployer \
  --password-file $HOME/.foundry/deployer.pw \
  --broadcast

# 2. Mint PRESALE_CAP to the presale address (separate step, needs MINTER_ROLE on the token)

# 3. Load allocations — see "Loading the allocation list" below
./script/cargar-lote.sh lotes/lote-01.csv

# 4. Record the approved list hash — AFTER all batches are loaded and reconciled
forge script script/PresaleOps.s.sol:PresaleOps \
  --sig "setAllocationListHash(address,bytes32)" \
  $PRESALE_ADDRESS $LIST_HASH \
  --rpc-url $AMOY_RPC_URL --account presaleAdmin \
  --password-file $HOME/.foundry/presale.pw --broadcast

# 5. Close the presale
forge script script/PresaleOps.s.sol:PresaleOps \
  --sig "finalize(address)" $PRESALE_ADDRESS \
  --rpc-url $AMOY_RPC_URL --account presaleAdmin \
  --password-file $HOME/.foundry/presale.pw --broadcast

# 6. Send the unsold portion to the treasury
forge script script/PresaleOps.s.sol:PresaleOps \
  --sig "withdrawUnallocated(address,address)" \
  $PRESALE_ADDRESS $TREASURY_ADDRESS \
  --rpc-url $AMOY_RPC_URL --account presaleAdmin \
  --password-file $HOME/.foundry/presale.pw --broadcast

# 7. After the deadline, sweep whatever was never claimed
forge script script/PresaleOps.s.sol:PresaleOps \
  --sig "sweepUnclaimed(address,address)" \
  $PRESALE_ADDRESS $TREASURY_ADDRESS \
  --rpc-url $AMOY_RPC_URL --account presaleAdmin \
  --password-file $HOME/.foundry/presale.pw --broadcast
```

### Loading the allocation list

Batch arrays are awkward to pass by hand (`forge --sig` wants `[a,b,c]` with **no spaces**, which
is unusable for 200 addresses), and every batch must be verified before the next one is sent.
`script/cargar-lote.sh` does both.

Split the final, address-consolidated list into numbered chunks of 100–200 rows first:

```bash
# lista-preventa.csv: one row per address, "0x<40 lowercase hex>,<amount in wei>", no header
split -l 200 -d --additional-suffix=.csv lista-preventa.csv lotes/lote-
```

Then send them one at a time:

```bash
export PRESALE_ADDRESS=0x...
export RPC_URL=$AMOY_RPC_URL
export KEYSTORE_ACCOUNT=presaleAdmin
export PASSWORD_FILE=$HOME/.foundry/presale.pw

./script/cargar-lote.sh lotes/lote-00.csv
./script/cargar-lote.sh lotes/lote-01.csv
# ...
```

For each chunk the script:

1. **Validates the file** — row format, lowercase addresses, integer wei amounts, no duplicate
   address within the chunk, and no more than 250 rows.
2. **Reads `totalAllocated` and `beneficiaryCount` before sending**, and checks `allocations()` for
   every address in the chunk. **If all of them already hold a balance it aborts**: that chunk has
   almost certainly already landed, and resending would double every allocation in it. If only some
   hold a balance it warns and asks for confirmation, since that may legitimately be buyers from an
   earlier phase.
3. Sends the batch.
4. **Verifies the deltas**: `totalAllocated` must have grown by exactly the chunk's sum, and
   `beneficiaryCount` by exactly the number of addresses that were new. If either does not match it
   exits non-zero and tells you not to continue.

Run them **one at a time, never in parallel**, and do not proceed past a failure.

**Steps 3 → 4 → 5 must happen in that order.** If the list hash is recorded before every batch is
loaded, it does not correspond to what ended up on chain and is worthless as evidence. Reconcile
`totalAllocated` and `beneficiaryCount` against the backend, and have a second person regenerate
the list independently, before recording the hash.

Use the encrypted keystore of `PRESALE_ADMIN_ADDRESS` for any `PresaleOps.s.sol` call — the
deployer key holds no role on the presale contract.

`deployer` and `PROTOCOL_ADMIN_ADDRESS` may still be the same centralized admin wallet for the rest
of the stack (token, staking, incentives). That broader centralization tradeoff is unchanged and
tracked separately; `PresaleAllocation.sol` specifically does not have it.

## Status

Verified on 2026-10-11 against Solidity 0.8.24 and OpenZeppelin v5.0.2:

- **`forge test`: 50 of 50 pass.** Coverage includes double-claim, rounding/dust, access control
  per function, batch length and cap, close idempotency, pause/unpause, the list-hash commitment,
  the buyer counter, the day +180 claim deadline with its treasury sweep, and the deadline
  extension by accumulated paused time.
- **Static analysis (Slither): no actionable findings in `PresaleAllocation.sol`.** Four findings
  touch it — `divide-before-multiply`, `incorrect-equality`, `timestamp` and `costly-loop` — and
  all four are expected consequences of the vesting design, documented for the external auditor.
- Measured gas: deployment 1,377,061; `claim()` 118,122 worst case; ~29,400 per address inside a
  batch. Contract size 6,560 bytes against the 24,576 limit. Load allocations in batches of 100–200.

Still open, and not blockers for the contract code:

- `forge coverage --ir-minimum` has not been run yet.
- Pin `evm_version` in `foundry.toml` before deploying (see **Build and test**).
- Testnet rehearsal with shortened periods, then external audit.
