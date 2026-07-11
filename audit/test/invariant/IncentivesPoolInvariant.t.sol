// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { TestBase } from "../utils/TestBase.sol";
import { HackToken } from "../../src/HackTokenERC20.sol";
import { IncentivesPool } from "../../src/IncentivesPool.sol";

/// @notice Stateful fuzz target demonstrating the accounting/asset mismatch in IncentivesPool.
contract IncentivesPoolInvariantTest is TestBase {
    HackToken internal token;
    IncentivesPool internal pool;

    function setUp() public {
        token = new HackToken();
        pool = new IncentivesPool(address(token));
        pool.grantRole(pool.DEPOSITOR_ROLE(), address(this));
    }

    function testFuzz_ReportedBalanceCanExceedActualAssets(uint96 rawAmount) public {
        uint256 amount = uint256(rawAmount);
        vm.assume(amount > 0);
        pool.deposit(amount, "invariant-counterexample");

        assertTrue(
            pool.poolBalance() > token.balanceOf(address(pool)),
            "expected accounting mismatch not reproduced"
        );
    }
}
