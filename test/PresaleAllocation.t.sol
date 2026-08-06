// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.24;

import { HackToken } from "../contracts/HackTokenERC20.sol";
import { PresaleAllocation } from "../contracts/PresaleAllocation.sol";
import { Vm } from "forge-std/Vm.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract PresaleAllocationTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    HackToken private token;
    PresaleAllocation private presale;

    address private admin = address(0xA11CE);
    address private buyer = address(0xB0B);
    address private other = address(0xC0DE);

    function setUp() public {
        vm.startPrank(admin);
        token = new HackToken();
        presale = new PresaleAllocation(address(token), 1_000_000 ether);
        token.mintTokens(address(presale), 1_000_000 ether);
        vm.stopPrank();
    }

    function testAllocateAndClaim() public {
        setUp();

        vm.prank(admin);
        presale.allocate(buyer, 100 ether);

        vm.prank(admin);
        presale.finalizePresale();
        vm.warp(block.timestamp + 30 days);

        require(presale.claimableBalance(buyer) == uint256(100 ether) / 3, "claimable mismatch");

        uint256 beforeBalance = token.balanceOf(buyer);
        vm.prank(buyer);
        presale.claim();

        require(
            token.balanceOf(buyer) == beforeBalance + uint256(100 ether) / 3, "transfer mismatch"
        );
        require(presale.claimableBalance(buyer) == 0, "claimable not cleared");
        require(presale.totalClaimed() == uint256(100 ether) / 3, "total claimed mismatch");
    }

    function testOnlyAdminCanAllocate() public {
        setUp();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                presale.ADMIN_ROLE()
            )
        );
        vm.prank(other);
        presale.allocate(buyer, 1 ether);
    }

    function testFinalizePreventsFurtherAllocation() public {
        setUp();

        vm.prank(admin);
        presale.finalizePresale();

        vm.expectRevert(abi.encodeWithSelector(PresaleAllocation.SaleFinalized.selector));
        vm.prank(admin);
        presale.allocate(buyer, 1 ether);
    }

    function testCapPreventsOverAllocation() public {
        setUp();

        vm.prank(admin);
        presale.allocate(buyer, 1_000_000 ether);

        vm.expectRevert(abi.encodeWithSelector(PresaleAllocation.CapExceeded.selector));
        vm.prank(admin);
        presale.allocate(other, 1 ether);
    }

    function testFinalizationReleasesOnlyUnsoldTokens() public {
        setUp();

        vm.prank(admin);
        presale.allocate(buyer, 100 ether);
        vm.prank(admin);
        presale.finalizePresale();

        uint256 beforeBalance = token.balanceOf(admin);
        vm.prank(admin);
        presale.withdrawUnallocated(admin);

        require(token.balanceOf(admin) == beforeBalance + 999_900 ether, "unsold amount mismatch");
        require(token.balanceOf(address(presale)) == 100 ether, "allocated escrow changed");
    }

    function testUnallocatedWithdrawalCanOnlyRunOnce() public {
        setUp();

        vm.prank(admin);
        presale.finalizePresale();
        vm.prank(admin);
        presale.withdrawUnallocated(admin);

        vm.expectRevert(abi.encodeWithSelector(PresaleAllocation.NothingToWithdraw.selector));
        vm.prank(admin);
        presale.withdrawUnallocated(admin);
    }

    function testVestingReleasesThreeMonthlyTranches() public {
        setUp();

        vm.prank(admin);
        presale.allocate(buyer, 99 ether);
        vm.prank(admin);
        presale.finalizePresale();
        uint256 vestingStart = presale.vestingStart();

        vm.warp(vestingStart + 29 days);
        require(presale.claimableBalance(buyer) == 0, "cliff bypassed");

        vm.warp(vestingStart + 30 days);
        require(presale.claimableBalance(buyer) == 33 ether, "first tranche mismatch");
        vm.prank(buyer);
        presale.claim();

        vm.warp(vestingStart + 60 days);
        require(presale.claimableBalance(buyer) == 33 ether, "second tranche mismatch");
        vm.prank(buyer);
        presale.claim();

        vm.warp(vestingStart + 90 days);
        require(presale.claimableBalance(buyer) == 33 ether, "third tranche mismatch");
    }
}
