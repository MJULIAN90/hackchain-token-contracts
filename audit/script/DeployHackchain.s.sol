// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { HackToken } from "../src/HackTokenERC20.sol";
import { IncentivesPool } from "../src/IncentivesPool.sol";
import { StakingContract } from "../src/StakingContract.sol";
import { ReferralSystem } from "../src/ReferralSystem.sol";
import { MembershipSystem } from "../src/MembershipSystem.sol";
import { PenaltySystem } from "../src/PenaltySystem.sol";
import { TalentBonuses } from "../src/TalentBonuses.sol";
import { EducatorBonuses } from "../src/EducatorBonuses.sol";
import { RecruiterBonuses } from "../src/RecruiterBonuses.sol";
import { EventRewards } from "../src/EventRewards.sol";
import { ReputationBonuses } from "../src/ReputationBunises.sol";

interface VmScript {
    function envAddress(string calldata name) external returns (address value);
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys the audited HackChain contracts and configures the required pool roles.
/// @dev This script preserves the audited source. It does not remediate the report findings.
contract DeployHackchain {
    VmScript internal constant vm =
        VmScript(address(uint160(uint256(keccak256("hevm cheat code")))));

    event ContractDeployed(string indexed name, address indexed deployedAt);

    function run() external {
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast();

        HackToken token = new HackToken();
        IncentivesPool pool = new IncentivesPool(address(token));
        StakingContract staking = new StakingContract(address(token), address(pool));
        ReferralSystem referrals = new ReferralSystem(address(pool), address(staking));
        MembershipSystem memberships = new MembershipSystem(address(token), address(pool), treasury);
        PenaltySystem penalties = new PenaltySystem(address(token), address(pool), treasury);
        TalentBonuses talentBonuses = new TalentBonuses(address(token), address(pool));
        EducatorBonuses educatorBonuses = new EducatorBonuses(address(pool));
        RecruiterBonuses recruiterBonuses = new RecruiterBonuses(address(pool));
        EventRewards eventRewards = new EventRewards(address(pool));
        ReputationBonuses reputationBonuses = new ReputationBonuses(address(pool));

        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(staking));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(referrals));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(talentBonuses));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(educatorBonuses));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(recruiterBonuses));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(eventRewards));
        pool.grantRole(pool.DISTRIBUTOR_ROLE(), address(reputationBonuses));

        pool.grantRole(pool.DEPOSITOR_ROLE(), address(memberships));
        pool.grantRole(pool.DEPOSITOR_ROLE(), address(penalties));

        vm.stopBroadcast();

        emit ContractDeployed("HackToken", address(token));
        emit ContractDeployed("IncentivesPool", address(pool));
        emit ContractDeployed("StakingContract", address(staking));
        emit ContractDeployed("ReferralSystem", address(referrals));
        emit ContractDeployed("MembershipSystem", address(memberships));
        emit ContractDeployed("PenaltySystem", address(penalties));
        emit ContractDeployed("TalentBonuses", address(talentBonuses));
        emit ContractDeployed("EducatorBonuses", address(educatorBonuses));
        emit ContractDeployed("RecruiterBonuses", address(recruiterBonuses));
        emit ContractDeployed("EventRewards", address(eventRewards));
        emit ContractDeployed("ReputationBonuses", address(reputationBonuses));
    }
}
