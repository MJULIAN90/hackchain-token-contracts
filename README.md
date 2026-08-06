# Hackchain HACK Token - Smart Contracts
Modular implementation of the 30 tokenomics mechanisms for the $HACK token.

## Architecture
Token logic is split into 11 independent contracts for security, auditability and scalability- instead of one monolithic contract.

| Contract | Mechanisms covered |
|---|---|
| HackTokenERC20.sol | Base ERC20 token (roles: MINTER,BURNER,PAUSER) |
| PresaleAllocation.sol | Presale allocation ledger with mint-on-claim |
| IncentivesPool.sol | Central treasury for all reward distributions |
| StakingContract.sol | 1,6 |
| ReferralSystem.sol | 2 |
| MembershipSystem.sol | 3,13 |
| PenaltySystem.sol | 7,9,14,25,26,30 |
| ReputationBonuses.sol | 15,16,17 |
| EventRewards.sol | 5,10,18,19 |
| EducatorBonuses.sol | 20,21,22,24 |
| RecruiterBonuses.sol | 27,28,29 |
| TalentBonuses.sol | 4,11,23 |
| ComissionSystem.sol | 8 |

## Access Control
All reward/penalty contracts use OpenZeppelin AccessControl. Roles are granted to contracts (not external wallets) where possible to minimize trust assumptions.

## Foundry
The repository now includes a self-contained Foundry setup.

```bash
forge build
forge test
```

See [INFORME_IMPLEMENTACION.md](INFORME_IMPLEMENTACION.md) for a full implementation report.
For deployment keys, use an encrypted keystore or hardware wallet. Do not keep raw
deployment private keys in `.env`.
Typical setup:

```bash
cast wallet import deployer --interactive
forge script script/DeployCore.s.sol:DeployCore \
  --rpc-url $AMOY_RPC_URL \
  --account deployer \
  --password-file $HOME/.foundry/deployer.pw \
  --broadcast
```

## Presale
`PresaleAllocation.sol` is the dedicated presale module.

- Admins assign allocations with `allocate()` or `allocateBatch()`.
- Buyers claim vested tranches with `claim()`.
- The full `PRESALE_CAP` is prefunded into the presale escrow at deployment, so every allocation is backed before it can be claimed.
- The public presale follows the whitepaper: one-month cliff and three equal monthly tranches.
- `finalizePresale()` freezes new allocations without blocking claims.
- After finalization, `withdrawUnallocated()` returns only the unsold portion of the cap to the admin.

## Deployment
Two Foundry scripts are included:

- `script/DeployCore.s.sol` deploys the full stack and wires roles.
- `script/PresaleOps.s.sol` handles presale allocations and finalization.

Recommended environment variables:

- `TREASURY_ADDRESS`
- `PROTOCOL_ADMIN_ADDRESS`
- `PRESALE_ADMIN_ADDRESS`
- `INITIAL_REWARD_POOL_FUNDING`
- `PRESALE_CAP`

The supplied `.env.example` uses the whitepaper allocations for public presale
(`100,000,000 HACK`, 10%) and incentives (`300,000,000 HACK`, 30%).

Example flow on Polygon Amoy:

```bash
forge script script/DeployCore.s.sol:DeployCore \
  --rpc-url $AMOY_RPC_URL \
  --account deployer \
  --password-file $HOME/.foundry/deployer.pw \
  --broadcast

forge script script/PresaleOps.s.sol:PresaleOps \
  --sig "allocate(address,address,uint256)" \
  $PRESALE_ADDRESS $BUYER_ADDRESS $AMOUNT_WEI \
  --rpc-url $AMOY_RPC_URL \
  --account deployer \
  --password-file $HOME/.foundry/deployer.pw \
  --broadcast

forge script script/PresaleOps.s.sol:PresaleOps \
  --sig "finalize(address)" \
  $PRESALE_ADDRESS \
  --rpc-url $AMOY_RPC_URL \
  --account deployer \
  --password-file $HOME/.foundry/deployer.pw \
  --broadcast

forge script script/PresaleOps.s.sol:PresaleOps \
  --sig "withdrawUnallocated(address,address)" \
  $PRESALE_ADDRESS $TREASURY_ADDRESS \
  --rpc-url $AMOY_RPC_URL \
  --account deployer \
  --password-file $HOME/.foundry/deployer.pw \
  --broadcast
```

`deployer`, `PROTOCOL_ADMIN_ADDRESS` and `PRESALE_ADMIN_ADDRESS` may be the same
centralized admin wallet. If they differ, use the encrypted keystore of
`PRESALE_ADMIN_ADDRESS` for `PresaleOps.s.sol`.

## Status
Contracts compile under Solidity 0.8.24 and the presale module is covered by Foundry tests.
