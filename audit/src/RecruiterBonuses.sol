// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RecruiterBonuses
 * @dev Handles recruiter-specific bonus mechanisms (27, 28, 29).
 * Mechanism 27: Registration bonus → 50,000 tokens (once ever, after 7 active days).
 * Mechanism 28: Hire 4 Talents in a month → 40,000 tokens.
 * Mechanism 29: KYC verification bonus → 200,000 tokens (once ever).
 * All bonuses verified off-chain by an enforcer before distribution.
 */
contract RecruiterBonuses is AccessControl, ReentrancyGuard {

    // --- Roles ---
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    // ENFORCER_ROLE: verifies conditions off-chain and triggers rewards
    bytes32 public constant ENFORCER_ROLE = keccak256("ENFORCER_ROLE");

    // --- Constants ---

    // Mechanism 27: Registration bonus
    uint256 public constant REGISTRATION_BONUS = 50_000 * 1e18;
    uint256 public constant MIN_ACTIVE_DAYS = 7;

    // Mechanism 28: Monthly hiring bonus
    uint256 public constant MONTHLY_HIRING_BONUS = 40_000 * 1e18;
    uint256 public constant MONTHLY_HIRING_REQUIRED = 4;

    // Mechanism 29: KYC verification bonus
    uint256 public constant KYC_BONUS = 200_000 * 1e18;

    // --- Structs ---

    /**
     * @dev Tracks registration info for a recruiter (mechanism 27).
     */
    struct RegistrationInfo {
        uint256 registeredAt;  // when the recruiter registered
        bool bonusClaimed;     // whether the registration bonus has been claimed
    }

    /**
     * @dev Tracks monthly hiring activity for a recruiter (mechanism 28).
     */
    struct MonthlyHiring {
        uint256 currentMonth;
        uint256 talentsHired;
        bool rewardClaimed;
    }

    // --- State ---
    address public incentivesPool;

    // Mechanism 27: recruiter => registration info
    mapping(address => RegistrationInfo) public registrationInfo;

    // Mechanism 27: tracks wallets that have already registered
    // prevents double registration with different wallets
    mapping(address => bool) public isRegistered;

    // Mechanism 28: recruiter => monthly hiring tracking
    mapping(address => MonthlyHiring) public monthlyHiring;

    // Mechanism 29: tracks if recruiter has received KYC bonus
    mapping(address => bool) public kycRewarded;

    // Mechanism 29: tracks if recruiter is KYC verified (used by other contracts)
    mapping(address => bool) public isKycVerified;

    // --- Custom Errors ---
    error InvalidAddress();
    error AlreadyRegistered();
    error NotRegistered();
    error RegistrationBonusAlreadyClaimed();
    error MinActiveDaysNotReached();
    error MonthlyRewardAlreadyClaimed();
    error NotEnoughHiringsThisMonth();
    error KycAlreadyRewarded();
    error NotKycVerified();

    // --- Events ---
    event RecruiterRegistered(address indexed recruiter, uint256 registeredAt);
    event RegistrationBonusClaimed(address indexed recruiter, uint256 amount);
    event TalentHiringRegistered(address indexed recruiter, uint256 talentsHired);
    event MonthlyHiringRewarded(address indexed recruiter, uint256 month, uint256 amount);
    event KycVerified(address indexed recruiter);
    event KycBonusClaimed(address indexed recruiter, uint256 amount);

    // --- Constructor ---
    /**
     * @dev Links RecruiterBonuses to IncentivesPool.
     * @param incentivesPool_ Address of the deployed IncentivesPool contract.
     */
    constructor(address incentivesPool_) {
        if (incentivesPool_ == address(0)) revert InvalidAddress();

        incentivesPool = incentivesPool_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(ENFORCER_ROLE, msg.sender);
    }

    // --- Mechanism 27: Registration bonus ---

    /**
     * @notice Register a new recruiter on the platform.
     * @dev Called by ENFORCER_ROLE when a recruiter joins.
     * Checks that the recruiter has no previous wallet registered.
     * The bonus is not distributed yet — only after 7 active days.
     * @param recruiter_ Address of the new recruiter.
     */
    function registerRecruiter(address recruiter_)
        external
        onlyRole(ENFORCER_ROLE)
    {
        if (recruiter_ == address(0)) revert InvalidAddress();
        if (isRegistered[recruiter_]) revert AlreadyRegistered();

        isRegistered[recruiter_] = true;
        registrationInfo[recruiter_] = RegistrationInfo({
            registeredAt: block.timestamp,
            bonusClaimed: false
        });

        emit RecruiterRegistered(recruiter_, block.timestamp);
    }

    /**
     * @notice Claim the registration bonus after 7 active days.
     * @dev Callable by the recruiter from their dashboard.
     * Requires at least 7 days since registration.
     * Only claimable once ever.
     */
    function claimRegistrationBonus() external nonReentrant {
        if (!isRegistered[msg.sender]) revert NotRegistered();

        RegistrationInfo storage info = registrationInfo[msg.sender];

        if (info.bonusClaimed) revert RegistrationBonusAlreadyClaimed();

        // Check 7 active days have passed since registration
        if (block.timestamp < info.registeredAt + (MIN_ACTIVE_DAYS * 1 days))
            revert MinActiveDaysNotReached();

        // Mark before external call (CEI pattern)
        info.bonusClaimed = true;

        IIncentivesPool(incentivesPool).distribute(
            msg.sender,
            REGISTRATION_BONUS,
            "recruiter_registration_bonus"
        );

        emit RegistrationBonusClaimed(msg.sender, REGISTRATION_BONUS);
    }

    // --- Mechanism 28: Monthly hiring bonus ---

    /**
     * @notice Register a Talent hiring for a recruiter.
     * @dev Called by ENFORCER_ROLE when a hiring is confirmed on the platform.
     * Resets the counter automatically when a new month starts.
     * @param recruiter_ Address of the recruiter.
     */
    function registerHiring(address recruiter_)
        external
        onlyRole(ENFORCER_ROLE)
    {
        if (recruiter_ == address(0)) revert InvalidAddress();

        uint256 currentMonth = block.timestamp / 30 days;
        MonthlyHiring storage hiring = monthlyHiring[recruiter_];

        // Reset counter if new month
        if (hiring.currentMonth != currentMonth) {
            hiring.currentMonth = currentMonth;
            hiring.talentsHired = 0;
            hiring.rewardClaimed = false;
        }

        hiring.talentsHired += 1;

        emit TalentHiringRegistered(recruiter_, hiring.talentsHired);
    }

    /**
     * @notice Claim the monthly hiring bonus.
     * @dev Callable by the recruiter once they have hired 4 Talents this month.
     * Only claimable once per month.
     */
    function claimMonthlyHiringBonus() external nonReentrant {
        uint256 currentMonth = block.timestamp / 30 days;
        MonthlyHiring storage hiring = monthlyHiring[msg.sender];

        // Reset if new month
        if (hiring.currentMonth != currentMonth) {
            hiring.currentMonth = currentMonth;
            hiring.talentsHired = 0;
            hiring.rewardClaimed = false;
        }

        if (hiring.rewardClaimed) revert MonthlyRewardAlreadyClaimed();
        if (hiring.talentsHired < MONTHLY_HIRING_REQUIRED)
            revert NotEnoughHiringsThisMonth();

        // Mark before external call (CEI pattern)
        hiring.rewardClaimed = true;

        IIncentivesPool(incentivesPool).distribute(
            msg.sender,
            MONTHLY_HIRING_BONUS,
            "recruiter_monthly_hiring_bonus"
        );

        emit MonthlyHiringRewarded(msg.sender, currentMonth, MONTHLY_HIRING_BONUS);
    }

    // --- Mechanism 29: KYC verification bonus ---

    /**
     * @notice Mark a recruiter as KYC verified and enable bonus claim.
     * @dev Called by ENFORCER_ROLE after the recruiter completes the
     * KYC process indicated by Hackchain.
     * Grants the recruiter a verified badge on the platform.
     * @param recruiter_ Address of the recruiter.
     */
    function verifyKyc(address recruiter_)
        external
        onlyRole(ENFORCER_ROLE)
    {
        if (recruiter_ == address(0)) revert InvalidAddress();
        if (kycRewarded[recruiter_]) revert KycAlreadyRewarded();

        isKycVerified[recruiter_] = true;

        emit KycVerified(recruiter_);
    }

    /**
     * @notice Claim the KYC verification bonus.
     * @dev Callable by the recruiter after being KYC verified.
     * Only claimable once ever.
     */
    function claimKycBonus() external nonReentrant {
        if (!isKycVerified[msg.sender]) revert NotKycVerified();
        if (kycRewarded[msg.sender]) revert KycAlreadyRewarded();

        // Mark before external call (CEI pattern)
        kycRewarded[msg.sender] = true;

        IIncentivesPool(incentivesPool).distribute(
            msg.sender,
            KYC_BONUS,
            "recruiter_kyc_bonus"
        );

        emit KycBonusClaimed(msg.sender, KYC_BONUS);
    }

    // --- Views ---

    /**
     * @notice Returns whether a recruiter is registered.
     */
    function getIsRegistered(address recruiter_) external view returns (bool) {
        return isRegistered[recruiter_];
    }

    /**
     * @notice Returns registration info for a recruiter.
     */
    function getRegistrationInfo(address recruiter_)
        external
        view
        returns (RegistrationInfo memory)
    {
        return registrationInfo[recruiter_];
    }

    /**
     * @notice Returns monthly hiring info for a recruiter.
     */
    function getMonthlyHiring(address recruiter_)
        external
        view
        returns (MonthlyHiring memory)
    {
        return monthlyHiring[recruiter_];
    }

    /**
     * @notice Returns whether a recruiter is KYC verified.
     * Called by other contracts to validate recruiter legitimacy.
     */
    function getIsKycVerified(address recruiter_) external view returns (bool) {
        return isKycVerified[recruiter_];
    }

    /**
     * @notice Returns how many hirings a recruiter has left this month.
     */
    function getHiringsLeft(address recruiter_) external view returns (uint256) {
        MonthlyHiring memory hiring = monthlyHiring[recruiter_];
        uint256 currentMonth = block.timestamp / 30 days;

        if (hiring.currentMonth != currentMonth) return MONTHLY_HIRING_REQUIRED;
        if (hiring.talentsHired >= MONTHLY_HIRING_REQUIRED) return 0;
        return MONTHLY_HIRING_REQUIRED - hiring.talentsHired;
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