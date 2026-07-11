.PHONY: build test test-security test-business test-invariant gas fmt clean

build:
	forge build

test:
	forge test -vv

test-security:
	forge test --match-path "test/security/*.t.sol" -vvvv

test-business:
	forge test --match-path "test/business/*.t.sol" -vvvv

test-invariant:
	forge test --match-path "test/invariant/*.t.sol" -vvvv

gas:
	forge test --gas-report

fmt:
	forge fmt --check test script

clean:
	forge clean
