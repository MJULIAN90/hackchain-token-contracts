// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { TestBase } from "../utils/TestBase.sol";
import { HackToken } from "../../src/HackTokenERC20.sol";
import { IncentivesPool } from "../../src/IncentivesPool.sol";
import { StakingContract } from "../../src/StakingContract.sol";
import { PenaltySystem } from "../../src/PenaltySystem.sol";
import { TalentBonuses } from "../../src/TalentBonuses.sol";
import { EventRewards } from "../../src/EventRewards.sol";

contract BusinessLogicPoCTest is TestBase {
    address internal constant OFFENDER = address(0xBAD);
    address internal constant BUYER = address(0xB0B);
    address internal constant FUNDER = address(0xF00D);
    address internal constant ORGANIZER_ONE = address(0x1111);
    address internal constant ORGANIZER_TWO = address(0x2222);
    address internal constant TREASURY = address(0x7777);

    function _tokenAndPool() internal returns (HackToken token, IncentivesPool pool) {
        token = new HackToken();
        pool = new IncentivesPool(address(token));
    }

    function _fund(HackToken token, IncentivesPool pool, uint256 amount) internal {
        token.mintTokens(address(this), amount);
        token.approve(address(pool), amount);
        pool.fundPool(amount);
    }

    /// Business mismatch: identity-fraud enforcement does not block the profile.
    function test_IdentityFraudPenaltyDoesNotBlockProfile() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        PenaltySystem penalties = new PenaltySystem(address(token), address(pool), TREASURY);
        pool.grantRole(pool.DEPOSITOR_ROLE(), address(penalties));
        token.mintTokens(OFFENDER, 10_000 ether);

        vm.prank(OFFENDER);
        token.approve(address(penalties), 1000 ether);
        penalties.applyIdentityFraudPenalty(OFFENDER);

        assertFalse(penalties.profileBlocked(OFFENDER), "profile was unexpectedly blocked");
    }

    /// H-05: moving all liquid tokens into staking reduces a wallet-based penalty base to zero.
    function test_StakingAllTokensMakesWalletPenaltyBaseZero() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        StakingContract staking = new StakingContract(address(token), address(pool));
        PenaltySystem penalties = new PenaltySystem(address(token), address(pool), TREASURY);
        token.mintTokens(OFFENDER, 10_000 ether);

        vm.startPrank(OFFENDER);
        token.approve(address(staking), 10_000 ether);
        staking.stake(10_000 ether, staking.ONE_YEAR());
        vm.stopPrank();

        vm.expectRevert();
        penalties.applyEducatorInactivityPenalty(OFFENDER);
        assertFalse(
            penalties.profileBlocked(OFFENDER),
            "profile was blocked after zero-base penalty reverted"
        );
    }

    /// H-05: the mass-sale eligibility calculation uses the post-sale wallet balance.
    function test_MassSaleThresholdUsesPostSaleBalance() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        PenaltySystem penalties = new PenaltySystem(address(token), address(pool), TREASURY);
        token.mintTokens(OFFENDER, 20_000_000 ether);

        vm.prank(OFFENDER);
        token.transfer(BUYER, 15_000_000 ether);

        vm.expectRevert();
        penalties.applyMassSalePenalty(OFFENDER, 15_000_000 ether, 1_000_000_000 ether);
        assertEq(token.balanceOf(OFFENDER), 5_000_000 ether, "unexpected offender balance");
    }

    /// M-02: the benefit remains active when another stake keeps the aggregate above the threshold.
    function test_NoCommissionSurvivesAfterQualifyingStakeIsRemoved() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        StakingContract staking = new StakingContract(address(token), address(pool));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(staking));
        _fund(token, pool, 2000 ether);
        token.mintTokens(OFFENDER, 200_000 ether);

        vm.startPrank(OFFENDER);
        token.approve(address(staking), 200_000 ether);
        staking.stake(100_000 ether, staking.ONE_YEAR());
        staking.stake(100_000 ether, staking.ONE_MONTH());
        staking.activateNoCommission();
        vm.warp(block.timestamp + 365 days + 1);
        staking.unstake(0);
        vm.stopPrank();

        assertTrue(staking.noCommissionActive(OFFENDER), "stale no-commission state was cleared");
    }

    /// L-05 / business gap: project funding accepts bytes32(0) and an unrestricted wallet.
    function test_ProjectFundingAcceptsZeroProjectIdAndUnrestrictedWallet() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        TalentBonuses bonuses = new TalentBonuses(address(token), address(pool));
        token.mintTokens(FUNDER, 1000 ether);

        vm.startPrank(FUNDER);
        token.approve(address(bonuses), 1000 ether);
        bonuses.fundProject(bytes32(0), 1000 ether);
        vm.stopPrank();

        (address funder, uint256 amount, uint256 distributed, uint256 remaining) =
            bonuses.getProjectFunding(bytes32(0));
        assertEq(funder, FUNDER, "unexpected project funder");
        assertEq(amount, 1000 ether, "unexpected funded amount");
        assertEq(distributed, 0, "unexpected distribution amount");
        assertEq(remaining, 1000 ether, "unexpected remaining amount");
    }

    /// Clarified rule: one promotional event identifier represents a single organizer reward.
    /// This is a conformance/regression test, not an audit finding.
    function test_PromoEventIdentifierCannotRewardTwoOrganizers() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        EventRewards eventsContract = new EventRewards(address(pool));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(eventsContract));
        _fund(token, pool, 60_000 ether);
        bytes32 eventId = keccak256("single-organizer-event");

        eventsContract.rewardPromoEvent(ORGANIZER_ONE, eventId, 10);
        vm.expectRevert();
        eventsContract.rewardPromoEvent(ORGANIZER_TWO, eventId, 10);
    }
}
