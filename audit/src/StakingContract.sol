// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title StakingContract
 * @dev Handles token staking for 1 month and 1 year periods.
 * Distributes rewards from IncentivesPool upon unstaking.
 * Also manages the no-commission benefit (mechanism 6).
 */
contract StakingContract is AccessControl, ReentrancyGuard {

    // --- Roles ---
    // ADMIN_ROLE: can update IncentivesPool address if needed
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // --- Staking periods ---
    uint256 public constant ONE_MONTH = 30 days;
    uint256 public constant ONE_YEAR = 365 days;

    // --- Staking requirements (mechanism 1) ---
    uint256 public constant MIN_STAKE_ONE_MONTH = 1_000 * 1e18;
    uint256 public constant MIN_STAKE_ONE_YEAR = 10_000 * 1e18;

    // --- Rewards (mechanism 1) ---
    uint256 public constant REWARD_ONE_MONTH = 50 * 1e18;
    uint256 public constant REWARD_ONE_YEAR = 1_000 * 1e18;

    // --- No-commission threshold (mechanism 6) ---
    uint256 public constant NO_COMMISSION_THRESHOLD = 100_000 * 1e18;

    // --- Structs ---
    /**
     * @dev Represents a single staking position.
     * A user can have multiple active stakes.
     */
    struct Stake {
        uint256 amount;       // tokens staked
        uint256 startTime;    // when the stake started
        uint256 duration;     // ONE_MONTH or ONE_YEAR
        uint256 reward;       // REWARD_ONE_MONTH or REWARD_ONE_YEAR
        bool active;          // false once unstaked
    }

    // --- State ---
    IERC20 public immutable hackToken;
    address public incentivesPool;

    // user address => list of their stakes
    mapping(address => Stake[]) public userStakes;

    // total tokens currently staked per user (used for mechanism 6)
    mapping(address => uint256) public totalStakedByUser;

    // mechanism 6: tracks if user has the no-commission badge active
    mapping(address => bool) public noCommissionActive;

    // --- Custom Errors ---
    error InvalidAddress();
    error AmountTooLow();
    error InvalidDuration();
    error StakeNotFound();
    error StakeAlreadyInactive();
    error StakingPeriodNotOver();
    error TransferFailed();
    error NoCommissionNotEligible();
    error NoCommissionAlreadyActive();
    error NoCommissionNotActive();

    // --- Events ---
    event Staked(address indexed user, uint256 amount, uint256 duration, uint256 stakeIndex);
    event Unstaked(address indexed user, uint256 amount, uint256 reward, uint256 stakeIndex);
    event NoCommissionActivated(address indexed user);
    event NoCommissionDeactivated(address indexed user);

    // --- Constructor ---
    /**
     * @dev Links StakingContract to HackToken and IncentivesPool.
     * @param hackToken_ Address of the deployed HackToken contract.
     * @param incentivesPool_ Address of the deployed IncentivesPool contract.
     */
    constructor(address hackToken_, address incentivesPool_) {
        if (hackToken_ == address(0)) revert InvalidAddress();
        if (incentivesPool_ == address(0)) revert InvalidAddress();

        hackToken = IERC20(hackToken_);
        incentivesPool = incentivesPool_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    // --- Staking ---

    /**
     * @notice Stake HACK tokens for 1 month or 1 year.
     * @dev User must approve this contract to spend their tokens first.
     * Mechanism 1: 1 month = 50 token reward, 1 year = 1000 token reward.
     * @param amount_ Amount of HACK tokens to stake.
     * @param duration_ Must be ONE_MONTH (30 days) or ONE_YEAR (365 days).
     */
    function stake(uint256 amount_, uint256 duration_) external nonReentrant {
        // Validate duration
        if (duration_ != ONE_MONTH && duration_ != ONE_YEAR) revert InvalidDuration();

        // Validate minimum amount per duration
        if (duration_ == ONE_MONTH && amount_ < MIN_STAKE_ONE_MONTH) revert AmountTooLow();
        if (duration_ == ONE_YEAR && amount_ < MIN_STAKE_ONE_YEAR) revert AmountTooLow();

        // Determine reward based on duration
        uint256 reward = duration_ == ONE_MONTH ? REWARD_ONE_MONTH : REWARD_ONE_YEAR;

        // Transfer tokens from user to this contract
        bool success = hackToken.transferFrom(msg.sender, address(this), amount_);
        if (!success) revert TransferFailed();

        // Register the stake
        userStakes[msg.sender].push(Stake({
            amount: amount_,
            startTime: block.timestamp,
            duration: duration_,
            reward: reward,
            active: true
        }));

        // Update total staked by user
        totalStakedByUser[msg.sender] += amount_;

        uint256 stakeIndex = userStakes[msg.sender].length - 1;
        emit Staked(msg.sender, amount_, duration_, stakeIndex);
    }

    /**
     * @notice Unstake tokens and claim reward after the staking period ends.
     * @dev Requests reward distribution from IncentivesPool.
     * @param stakeIndex_ Index of the stake in the user's stakes array.
     */
    function unstake(uint256 stakeIndex_) external nonReentrant {
        Stake storage userStake = userStakes[msg.sender][stakeIndex_];

        // Validate stake exists and is active
        if (stakeIndex_ >= userStakes[msg.sender].length) revert StakeNotFound();
        if (!userStake.active) revert StakeAlreadyInactive();

        // Check staking period is over
        if (block.timestamp < userStake.startTime + userStake.duration)
            revert StakingPeriodNotOver();

        // Mark as inactive before transfers (CEI pattern — prevents reentrancy)
        userStake.active = false;
        totalStakedByUser[msg.sender] -= userStake.amount;

        // Return staked tokens to user
        bool success = hackToken.transfer(msg.sender, userStake.amount);
        if (!success) revert TransferFailed();

        // Request reward from IncentivesPool
        IIncentivesPool(incentivesPool).distribute(
            msg.sender,
            userStake.reward,
            "staking_reward"
        );

        // If no-commission was active and user no longer qualifies, deactivate it
        if (noCommissionActive[msg.sender] &&
            totalStakedByUser[msg.sender] < NO_COMMISSION_THRESHOLD) {
            noCommissionActive[msg.sender] = false;
            emit NoCommissionDeactivated(msg.sender);
        }

        emit Unstaked(msg.sender, userStake.amount, userStake.reward, stakeIndex_);
    }

    // --- Mechanism 6: No-commission benefit ---

    /**
     * @notice Activate the no-commission benefit from the user's dashboard.
     * @dev Mechanism 6: requires 100,000 tokens staked for at least 12 months.
     * Grants the user a badge and exempts them from platform commissions.
     */
    function activateNoCommission() external {
        if (noCommissionActive[msg.sender]) revert NoCommissionAlreadyActive();
        if (!_isEligibleForNoCommission(msg.sender)) revert NoCommissionNotEligible();

        noCommissionActive[msg.sender] = true;
        emit NoCommissionActivated(msg.sender);
    }

    /**
     * @notice Deactivate the no-commission benefit manually.
     */
    function deactivateNoCommission() external {
        if (!noCommissionActive[msg.sender]) revert NoCommissionNotActive();
        noCommissionActive[msg.sender] = false;
        emit NoCommissionDeactivated(msg.sender);
    }

    // --- Views ---

    /**
     * @notice Returns all stakes for a given user.
     */
    function getUserStakes(address user_) external view returns (Stake[] memory) {
        return userStakes[user_];
    }

    /**
     * @notice Returns whether a user currently has the no-commission benefit active.
     * Called by CommissionSystem to check if user should be charged.
     */
    function hasNoCommission(address user_) external view returns (bool) {
        return noCommissionActive[user_];
    }

    /**
     * @notice Returns the total amount of tokens staked by a user.
     */
    function getTotalStaked(address user_) external view returns (uint256) {
        return totalStakedByUser[user_];
    }

    // --- Internal ---

    /**
     * @dev Checks if a user qualifies for the no-commission benefit.
     * Requires at least one active stake of 100,000+ tokens for ONE_YEAR duration.
     */
    function _isEligibleForNoCommission(address user_) internal view returns (bool) {
        Stake[] memory stakes = userStakes[user_];
        for (uint256 i = 0; i < stakes.length; i++) {
            if (
                stakes[i].active &&
                stakes[i].amount >= NO_COMMISSION_THRESHOLD &&
                stakes[i].duration == ONE_YEAR
            ) {
                return true;
            }
        }
        return false;
    }

    // --- Admin ---

    /**
     * @notice Update the IncentivesPool address if it changes.
     * @dev Only callable by ADMIN_ROLE.
     */
    function setIncentivesPool(address newPool_) external onlyRole(ADMIN_ROLE) {
        if (newPool_ == address(0)) revert InvalidAddress();
        incentivesPool = newPool_;
    }
}

// --- Interface ---
/**
 * @dev Minimal interface to call IncentivesPool.distribute() from StakingContract.
 * Avoids importing the full contract.
 */
interface IIncentivesPool {
    function distribute(address to_, uint256 amount_, string calldata reason_) external;
}
