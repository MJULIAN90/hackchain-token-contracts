// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PresaleAllocation
 * @dev Administrative allocation ledger for the HACK presale.
 * The presale cap is minted to this contract at deployment. Claims transfer
 * from that escrow, ensuring every assigned allocation is backed by tokens.
 */
contract PresaleAllocation is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 public constant CLIFF_DURATION = 30 days;
    uint256 public constant RELEASE_INTERVAL = 30 days;
    uint256 public constant RELEASE_PERIODS = 3;

    IERC20 public immutable hackToken;
    uint256 public immutable presaleCap;

    uint256 public totalAllocated;
    uint256 public totalClaimed;
    uint256 public vestingStart;
    bool public finalized;
    bool public unallocatedWithdrawn;

    mapping(address => uint256) public allocations;
    mapping(address => uint256) public claimed;

    error InvalidAddress();
    error AmountMustBeGreaterThanZero();
    error CapExceeded();
    error SaleFinalized();
    error SaleNotFinalized();
    error NothingToClaim();
    error NothingToWithdraw();
    error LengthMismatch();

    event AllocationAssigned(address indexed beneficiary, uint256 amount, uint256 totalAllocation);
    event Claimed(address indexed beneficiary, uint256 amount);
    event PresaleFinalized(uint256 totalAllocated, uint256 totalClaimed);
    event UnallocatedWithdrawn(address indexed recipient, uint256 amount);

    constructor(address hackToken_, uint256 presaleCap_) {
        if (hackToken_ == address(0)) revert InvalidAddress();
        if (presaleCap_ == 0) revert AmountMustBeGreaterThanZero();

        hackToken = IERC20(hackToken_);
        presaleCap = presaleCap_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function allocate(address beneficiary_, uint256 amount_) external onlyRole(ADMIN_ROLE) {
        _allocate(beneficiary_, amount_);
    }

    function allocateBatch(address[] calldata beneficiaries_, uint256[] calldata amounts_)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (finalized) revert SaleFinalized();
        if (beneficiaries_.length != amounts_.length) revert LengthMismatch();

        for (uint256 i; i < beneficiaries_.length;) {
            _allocate(beneficiaries_[i], amounts_[i]);
            unchecked {
                ++i;
            }
        }
    }

    function claim() external nonReentrant {
        uint256 claimable = claimableBalance(msg.sender);
        if (claimable == 0) revert NothingToClaim();

        claimed[msg.sender] += claimable;
        totalClaimed += claimable;

        hackToken.safeTransfer(msg.sender, claimable);

        emit Claimed(msg.sender, claimable);
    }

    function claimableBalance(address beneficiary_) public view returns (uint256) {
        return vestedBalance(beneficiary_) - claimed[beneficiary_];
    }

    function vestedBalance(address beneficiary_) public view returns (uint256) {
        if (!finalized || block.timestamp < vestingStart + CLIFF_DURATION) return 0;

        uint256 releasedPeriods = (block.timestamp - vestingStart) / RELEASE_INTERVAL;
        if (releasedPeriods >= RELEASE_PERIODS) return allocations[beneficiary_];

        return (allocations[beneficiary_] * releasedPeriods) / RELEASE_PERIODS;
    }

    function finalizePresale() external onlyRole(ADMIN_ROLE) {
        if (!finalized) {
            finalized = true;
            vestingStart = block.timestamp;
            emit PresaleFinalized(totalAllocated, totalClaimed);
        }
    }

    /// @notice Returns the unsold part of the prefunded cap after finalization.
    function withdrawUnallocated(address recipient_) external onlyRole(ADMIN_ROLE) {
        if (!finalized) revert SaleNotFinalized();
        if (recipient_ == address(0)) revert InvalidAddress();
        if (unallocatedWithdrawn) revert NothingToWithdraw();

        uint256 amount = presaleCap - totalAllocated;
        if (amount == 0) revert NothingToWithdraw();

        unallocatedWithdrawn = true;
        hackToken.safeTransfer(recipient_, amount);

        emit UnallocatedWithdrawn(recipient_, amount);
    }

    function _allocate(address beneficiary_, uint256 amount_) internal {
        if (finalized) revert SaleFinalized();
        if (beneficiary_ == address(0)) revert InvalidAddress();
        if (amount_ == 0) revert AmountMustBeGreaterThanZero();
        if (totalAllocated + amount_ > presaleCap) revert CapExceeded();

        allocations[beneficiary_] += amount_;
        totalAllocated += amount_;

        emit AllocationAssigned(beneficiary_, amount_, allocations[beneficiary_]);
    }
}
