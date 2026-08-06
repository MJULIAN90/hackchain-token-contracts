// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { PresaleAllocation } from "../contracts/PresaleAllocation.sol";

/**
 * @title PresaleOps
 * @dev Operational helper for presale allocation management.
 * Use `forge script ... --sig` to call the desired function on Amoy or Polygon.
 */
contract PresaleOps is Script {
    function allocate(address presale_, address beneficiary_, uint256 amount_) external {
        vm.startBroadcast();
        PresaleAllocation(presale_).allocate(beneficiary_, amount_);
        vm.stopBroadcast();
    }

    function allocateBatch(
        address presale_,
        address[] calldata beneficiaries_,
        uint256[] calldata amounts_
    ) external {
        vm.startBroadcast();
        PresaleAllocation(presale_).allocateBatch(beneficiaries_, amounts_);
        vm.stopBroadcast();
    }

    function finalize(address presale_) external {
        vm.startBroadcast();
        PresaleAllocation(presale_).finalizePresale();
        vm.stopBroadcast();
    }

    function withdrawUnallocated(address presale_, address recipient_) external {
        vm.startBroadcast();
        PresaleAllocation(presale_).withdrawUnallocated(recipient_);
        vm.stopBroadcast();
    }
}
