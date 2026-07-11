// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TalentBonuses
 * @dev Handles talent-related bonus mechanisms (4, 11, 23).
 * Mechanism 4:  New tokenized schooling degree → 50,000 tokens (Talent, Educator, Recruiter).
 * Mechanism 11: Talent hired on the platform → 5,000 tokens (once per month).
 * Mechanism 23: Open source project funding by Educator/Recruiter, split among Talents.
 * Mechanisms 4 and 11 are verified off-chain by an enforcer.
 * Mechanism 23 is funded directly by the sponsor, not from IncentivesPool.
 */
contract TalentBonuses is AccessControl, ReentrancyGuard {

    // --- Roles ---
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    // ENFORCER_ROLE: verifies conditions off-chain and triggers rewards
    bytes32 public constant ENFORCER_ROLE = keccak256("ENFORCER_ROLE");

    // --- Constants ---

    // Mechanism 4: Schooling degree bonus
    uint256 public constant SCHOOLING_DEGREE_REWARD = 50_000 * 1e18;

    // Mechanism 11: Talent hired bonus
    uint256 public constant TALENT_HIRED_REWARD = 5_000 * 1e18;

    // Mechanism 23: Allowed funding amounts for open source projects
    uint256 public constant FUNDING_TIER_1 = 1_000 * 1e18;
    uint256 public constant FUNDING_TIER_2 = 10_000 * 1e18;
    uint256 public constant FUNDING_TIER_3 = 100_000 * 1e18;

    // --- State ---
    IERC20 public immutable hackToken;
    address public incentivesPool;

    // Mechanism 4: user => degree level => already rewarded
    // prevents double rewarding the same degree level
    mapping(address => mapping(bytes32 => bool)) public degreeRewarded;

    // Mechanism 11: talent => month => hiring already rewarded this month
    mapping(address => uint256) public lastHiringRewardMonth;

    // Mechanism 23: projectId => sponsor (who funded it)
    mapping(bytes32 => address) public projectSponsor;

    // Mechanism 23: projectId => total amount funded
    mapping(bytes32 => uint256) public projectFundedAmount;

    // Mechanism 23: projectId => total amount distributed to talents so far
    mapping(bytes32 => uint256) public projectDistributedAmount;

    // --- Custom Errors ---
    error InvalidAddress();
    error InvalidAmount();
    error DegreeAlreadyRewarded();
    error HiringAlreadyRewardedThisMonth();
    error InvalidFundingTier();
    error TransferFailed();
    error ProjectNotFunded();
    error ExceedsFundedAmount();
    error EmptyTalentsList();

    // --- Events ---
    event SchoolingDegreeRewarded(address indexed user, bytes32 degreeId, uint256 amount);
    event TalentHiredRewarded(address indexed talent, uint256 month, uint256 amount);
    event ProjectFunded(bytes32 indexed projectId, address indexed sponsor, uint256 amount);
    event ProjectDistributed(bytes32 indexed projectId, address indexed talent, uint256 amount);

    // --- Constructor ---
    /**
     * @dev Links TalentBonuses to HackToken and IncentivesPool.
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
        _grantRole(ENFORCER_ROLE, msg.sender);
    }

    // --- Mechanism 4: Schooling degree bonus ---

    /**
     * @notice Reward a user for obtaining a new tokenized schooling degree.
     * @dev Only callable by ENFORCER_ROLE after verifying the degree is
     * implemented in the user's tokenized identity. Applies to Talent,
     * Educator and Recruiter alike.
     * @param user_ Address of the user who obtained the degree.
     * @param degreeId_ Unique identifier for the degree level
     * (e.g. keccak256("bachelor"), keccak256("master"), keccak256("phd")).
     * Prevents the same degree level from being rewarded twice.
     */
    function rewardSchoolingDegree(address user_, bytes32 degreeId_)
        external
        onlyRole(ENFORCER_ROLE)
        nonReentrant
    {
        if (user_ == address(0)) revert InvalidAddress();
        if (degreeRewarded[user_][degreeId_]) revert DegreeAlreadyRewarded();

        // Mark before external call (CEI pattern)
        degreeRewarded[user_][degreeId_] = true;

        IIncentivesPool(incentivesPool).distribute(
            user_,
            SCHOOLING_DEGREE_REWARD,
            "schooling_degree_reward"
        );

        emit SchoolingDegreeRewarded(user_, degreeId_, SCHOOLING_DEGREE_REWARD);
    }

    // --- Mechanism 11: Talent hired bonus ---

    /**
     * @notice Reward a Talent for being hired on the platform.
     * @dev Only callable by ENFORCER_ROLE after verifying the hiring is
     * registered on the platform. Only one reward per Talent per month.
     * @param talent_ Address of the hired Talent.
     */
    function rewardTalentHired(address talent_)
        external
        onlyRole(ENFORCER_ROLE)
        nonReentrant
    {
        if (talent_ == address(0)) revert InvalidAddress();

        uint256 currentMonth = block.timestamp / 30 days;
        if (lastHiringRewardMonth[talent_] == currentMonth)
            revert HiringAlreadyRewardedThisMonth();

        // Mark before external call (CEI pattern)
        lastHiringRewardMonth[talent_] = currentMonth;

        IIncentivesPool(incentivesPool).distribute(
            talent_,
            TALENT_HIRED_REWARD,
            "talent_hired_reward"
        );

        emit TalentHiredRewarded(talent_, currentMonth, TALENT_HIRED_REWARD);
    }

    // --- Mechanism 23: Open source project funding ---

    /**
     * @notice Fund an open source project worked on by Talents.
     * @dev Called by an Educator or Recruiter who wants to sponsor the project.
     * Sponsor must approve this contract to spend their tokens first.
     * Amount must match one of the three allowed tiers: 1,000 / 10,000 / 100,000.
     * Tokens are held in this contract until distributed to Talents individually.
     * @param projectId_ Unique identifier for the project
     * (e.g. keccak256 of the GitHub repo URL).
     * @param amount_ Amount to fund — must be 1,000, 10,000 or 100,000 tokens.
     */
    function fundProject(bytes32 projectId_, uint256 amount_) external nonReentrant {
        if (
            amount_ != FUNDING_TIER_1 &&
            amount_ != FUNDING_TIER_2 &&
            amount_ != FUNDING_TIER_3
        ) revert InvalidFundingTier();

        bool success = hackToken.transferFrom(msg.sender, address(this), amount_);
        if (!success) revert TransferFailed();

        projectSponsor[projectId_] = msg.sender;
        projectFundedAmount[projectId_] += amount_;

        emit ProjectFunded(projectId_, msg.sender, amount_);
    }

    /**
     * @notice Distribute funded tokens individually to Talents involved in a project.
     * @dev Only callable by ENFORCER_ROLE after verifying that all recipients
     * are Talents integrated into the open source project on GitHub.
     * Can be called multiple times for the same project until fully distributed.
     * @param projectId_ Unique identifier for the project.
     * @param talents_ Array of Talent addresses involved in the project.
     * @param amounts_ Array of amounts to send to each Talent (same order as talents_).
     */
    function distributeToTalents(
        bytes32 projectId_,
        address[] calldata talents_,
        uint256[] calldata amounts_
    ) external onlyRole(ENFORCER_ROLE) nonReentrant {
        if (talents_.length == 0) revert EmptyTalentsList();
        require(talents_.length == amounts_.length, "Arrays length mismatch");
        if (projectSponsor[projectId_] == address(0)) revert ProjectNotFunded();

        uint256 totalToDistribute = 0;
        for (uint256 i = 0; i < amounts_.length; i++) {
            totalToDistribute += amounts_[i];
        }

        uint256 remaining = projectFundedAmount[projectId_] - projectDistributedAmount[projectId_];
        if (totalToDistribute > remaining) revert ExceedsFundedAmount();

        // Update distributed amount before transfers (CEI pattern)
        projectDistributedAmount[projectId_] += totalToDistribute;

        for (uint256 i = 0; i < talents_.length; i++) {
            if (talents_[i] == address(0)) revert InvalidAddress();
            if (amounts_[i] == 0) revert InvalidAmount();

            bool success = hackToken.transfer(talents_[i], amounts_[i]);
            if (!success) revert TransferFailed();

            emit ProjectDistributed(projectId_, talents_[i], amounts_[i]);
        }
    }

    // --- Views ---

    /**
     * @notice Returns whether a user has been rewarded for a specific degree level.
     */
    function hasDegreeReward(address user_, bytes32 degreeId_) external view returns (bool) {
        return degreeRewarded[user_][degreeId_];
    }

    /**
     * @notice Returns the last month a Talent received the hiring reward.
     */
    function getLastHiringRewardMonth(address talent_) external view returns (uint256) {
        return lastHiringRewardMonth[talent_];
    }

    /**
     * @notice Returns funding info for a project.
     */
    function getProjectFunding(bytes32 projectId_)
        external
        view
        returns (address sponsor, uint256 funded, uint256 distributed, uint256 remaining)
    {
        sponsor = projectSponsor[projectId_];
        funded = projectFundedAmount[projectId_];
        distributed = projectDistributedAmount[projectId_];
        remaining = funded - distributed;
    }

    // --- Admin ---

    /**
     * @notice Update the IncentivesPool address.
     */
    function setIncentivesPool(address newPool_) external onlyRole(ADMIN_ROLE) {
        if (newPool_ == address(0)) revert InvalidAddress();
        incentivesPool = newPool_;
    }
}

// --- Interface ---
interface IIncentivesPool {
    function distribute(address to_, uint256 amount_, string calldata reason_) external;
}