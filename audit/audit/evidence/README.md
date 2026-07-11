# Foundry evidence

- `audited-commit.txt`: source commit supplied for the audit.
- `contract-sha256.txt`: SHA-256 hashes for the exact contracts under `src/`.
- `forge-build.txt`: successful Foundry compilation evidence.
- `forge-test.txt`: successful execution of all Solidity PoCs and fuzz tests.
- `forge-fmt.txt`: formatting verification for the Foundry-native tests and scripts.

The audited `src/` files are preserved byte-for-byte, so formatting checks intentionally target only
`test/` and `script/`.
