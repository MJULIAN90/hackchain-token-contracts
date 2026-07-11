# Foundry test matrix

| Test file | Coverage |
|---|---|
| `test/security/SecurityPoC.t.sol` | Referral timing, principal lock, no-commission timing, self-generated views, voluntary penalties, pool accounting, reputation epoch boundary, duplicate hiring rewards, split authority, invalid stake index |
| `test/business/BusinessLogicPoC.t.sol` | Identity fraud profile state, movable penalty base, post-sale mass-sale calculation, stale no-commission state, unrestricted project funding, promotional event identifier regression |
| `test/invariant/IncentivesPoolInvariant.t.sol` | Fuzzed counterexample where reported pool balance exceeds actual token assets |

Run all tests with:

```bash
forge test -vv
```

Run only security PoCs:

```bash
forge test --match-path "test/security/*.t.sol" -vvvv
```

Run business-logic PoCs:

```bash
forge test --match-path "test/business/*.t.sol" -vvvv
```

Run fuzz/invariant-oriented tests:

```bash
forge test --match-path "test/invariant/*.t.sol" -vvvv
```
