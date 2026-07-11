# HackChain Smart Contract Audit — Foundry Repository

Final, self-contained Foundry repository for the audited HackChain smart contracts.

## What is included

- Audited Solidity source in `src/`.
- Security and business-logic PoCs written entirely in Solidity.
- Fuzz/invariant-oriented tests using Foundry cheatcodes.
- Foundry deployment and funding scripts.
- Vendored OpenZeppelin Contracts 5.0.2 dependency.
- Structured findings, business documents, evidence, and architecture diagram.
- Auditor identification for Julian Ruiz.

## Requirements

Install the native Foundry toolchain (`forge`, `cast`, and `anvil`). Solidity 0.8.24 is pinned in
`foundry.toml`.

## Build

```bash
forge build
```

## Test

```bash
forge test -vv
forge test --match-path "test/security/*.t.sol" -vvvv
forge test --match-path "test/business/*.t.sol" -vvvv
forge test --match-path "test/invariant/*.t.sol" -vvvv
forge test --gas-report
```

For CI-level fuzz settings:

```bash
FOUNDRY_PROFILE=ci forge test
```

## Format

```bash
forge fmt --check test script
```

## Local deployment

```bash
cp .env.example .env
anvil

forge script script/DeployHackchain.s.sol:DeployHackchain \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvvv
```

## Fund the incentives pool

```bash
forge script script/FundIncentivesPool.s.sol:FundIncentivesPool \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvvv
```

## Repository structure

```text
src/                  Audited contracts
test/security/        Technical security PoCs
test/business/        Business-logic PoCs and conformance checks
test/invariant/       Fuzz/invariant counterexamples
script/               Foundry deployment and operational scripts
lib/                  Vendored Solidity dependencies
audit/reports/        Final Spanish and English audit reports
audit/findings/       Findings in CSV and JSON
audit/business-docs/  Business model and whitepaper sources
audit/diagrams/       User/contract interaction diagram
audit/evidence/       Audited commit and source hashes
```
