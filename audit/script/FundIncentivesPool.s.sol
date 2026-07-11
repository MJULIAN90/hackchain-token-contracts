// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IncentivesPool } from "../src/IncentivesPool.sol";

interface VmFundScript {
    function envAddress(string calldata name) external returns (address value);
    function envUint(string calldata name) external returns (uint256 value);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Approves and funds an already deployed IncentivesPool.
contract FundIncentivesPool {
    VmFundScript internal constant vm =
        VmFundScript(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external {
        address tokenAddress = vm.envAddress("HACK_TOKEN_ADDRESS");
        address poolAddress = vm.envAddress("INCENTIVES_POOL_ADDRESS");
        uint256 amount = vm.envUint("FUND_AMOUNT");

        vm.startBroadcast();
        IERC20(tokenAddress).approve(poolAddress, amount);
        IncentivesPool(poolAddress).fundPool(amount);
        vm.stopBroadcast();
    }
}
