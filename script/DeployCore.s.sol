// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";

import { HackToken } from "../contracts/HackTokenERC20.sol";
import { IncentivesPool } from "../contracts/IncentivesPool.sol";
import { StakingContract } from "../contracts/StakingContract.sol";
import { ReferralSystem } from "../contracts/ReferralSystem.sol";
import { MembershipSystem } from "../contracts/MembershipSystem.sol";
import { PenaltySystem } from "../contracts/PenaltySystem.sol";
import { EventRewards } from "../contracts/EventRewards.sol";
import { EducatorBonuses } from "../contracts/EducatorBonuses.sol";
import { RecruiterBonuses } from "../contracts/RecruiterBonuses.sol";
import { TalentBonuses } from "../contracts/TalentBonuses.sol";
import { CommissionSystem } from "../contracts/ComissionSystem.sol";
import { ReputationBonuses } from "../contracts/ReputationBunises.sol";
import { PresaleAllocation } from "../contracts/PresaleAllocation.sol";

/**
 * @title DeployCore
 * @dev Deploys the full HACK stack and wires the production roles.
 * Use on Polygon Amoy first, then on Polygon mainnet once verified.
 */
contract DeployCore is Script {
    uint256 internal constant MAX_HACK_SUPPLY = 1_000_000_000 ether;

    error InvalidDeploymentConfiguration();
    error AllocationsExceedMaxSupply();

    function run() external returns (Deployment memory deployment) {
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address protocolAdmin = vm.envAddress("PROTOCOL_ADMIN_ADDRESS");
        uint256 rewardPoolFunding = vm.envUint("INITIAL_REWARD_POOL_FUNDING");
        uint256 presaleCap = vm.envUint("PRESALE_CAP");
        address presaleAdmin = vm.envAddress("PRESALE_ADMIN_ADDRESS");

        if (treasury == address(0) || protocolAdmin == address(0) || presaleAdmin == address(0)) {
            revert InvalidDeploymentConfiguration();
        }
        if (presaleCap + rewardPoolFunding > MAX_HACK_SUPPLY) revert AllocationsExceedMaxSupply();

        vm.startBroadcast();
        address broadcaster = msg.sender;

        HackToken token = new HackToken();
        IncentivesPool incentivesPool = new IncentivesPool(address(token));
        StakingContract staking = new StakingContract(address(token), address(incentivesPool));
        ReferralSystem referral = new ReferralSystem(address(incentivesPool), address(staking));
        MembershipSystem membership =
            new MembershipSystem(address(token), address(incentivesPool), treasury);
        PenaltySystem penalty = new PenaltySystem(address(token), address(incentivesPool), treasury);
        EventRewards eventRewards = new EventRewards(address(incentivesPool));
        EducatorBonuses educatorBonuses = new EducatorBonuses(address(incentivesPool));
        RecruiterBonuses recruiterBonuses = new RecruiterBonuses(address(incentivesPool));
        TalentBonuses talentBonuses = new TalentBonuses(address(token), address(incentivesPool));
        CommissionSystem commission = new CommissionSystem(address(token), treasury);
        ReputationBonuses reputation = new ReputationBonuses(address(incentivesPool));
        // presaleAdmin (the presale multisig) receives every administrative role on the presale
        // contract directly from its constructor now — the broadcaster never holds them, so there
        // is nothing to revoke afterwards and no window where the deployer is a de facto co-admin.
        PresaleAllocation presale = new PresaleAllocation(address(token), presaleCap, presaleAdmin);

        _configureToken(token, protocolAdmin);
        _configurePool(
            incentivesPool,
            staking,
            referral,
            eventRewards,
            educatorBonuses,
            recruiterBonuses,
            talentBonuses,
            reputation,
            membership,
            penalty,
            protocolAdmin
        );
        _configureAdminRoles(
            staking,
            referral,
            membership,
            penalty,
            eventRewards,
            educatorBonuses,
            recruiterBonuses,
            talentBonuses,
            commission,
            reputation,
            protocolAdmin
        );

        if (protocolAdmin != broadcaster) {
            token.transferOwnershipCustom(protocolAdmin);
        }

        // Prefund the escrow so assigned presale tokens are always claimable.
        token.mintTokens(address(presale), presaleCap);

        if (rewardPoolFunding > 0) {
            token.mintTokens(broadcaster, rewardPoolFunding);
            token.approve(address(incentivesPool), rewardPoolFunding);
            incentivesPool.fundPool(rewardPoolFunding);
        }

        // No post-hoc presale.grantRole(...) here anymore: presaleAdmin already holds every role
        // from the constructor call above, and the broadcaster now has none to grant from even if
        // this were re-added by mistake.

        vm.stopBroadcast();

        deployment = Deployment({
            token: address(token),
            incentivesPool: address(incentivesPool),
            staking: address(staking),
            referral: address(referral),
            membership: address(membership),
            penalty: address(penalty),
            eventRewards: address(eventRewards),
            educatorBonuses: address(educatorBonuses),
            recruiterBonuses: address(recruiterBonuses),
            talentBonuses: address(talentBonuses),
            commission: address(commission),
            reputation: address(reputation),
            presale: address(presale)
        });
    }

    function _configureToken(HackToken token, address protocolAdmin) internal {
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        token.grantRole(token.MINTER_ROLE(), protocolAdmin);
        token.grantRole(token.BURNER_ROLE(), protocolAdmin);
        token.grantRole(token.PAUSER_ROLE(), protocolAdmin);
    }

    function _configurePool(
        IncentivesPool incentivesPool,
        StakingContract staking,
        ReferralSystem referral,
        EventRewards eventRewards,
        EducatorBonuses educatorBonuses,
        RecruiterBonuses recruiterBonuses,
        TalentBonuses talentBonuses,
        ReputationBonuses reputation,
        MembershipSystem membership,
        PenaltySystem penalty,
        address protocolAdmin
    ) internal {
        incentivesPool.grantRole(incentivesPool.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        incentivesPool.grantRole(incentivesPool.DISTRIBUTOR_ROLE(), address(staking));
        incentivesPool.grantRole(incentivesPool.DISTRIBUTOR_ROLE(), address(referral));
        incentivesPool.grantRole(incentivesPool.DISTRIBUTOR_ROLE(), address(eventRewards));
        incentivesPool.grantRole(incentivesPool.DISTRIBUTOR_ROLE(), address(educatorBonuses));
        incentivesPool.grantRole(incentivesPool.DISTRIBUTOR_ROLE(), address(recruiterBonuses));
        incentivesPool.grantRole(incentivesPool.DISTRIBUTOR_ROLE(), address(talentBonuses));
        incentivesPool.grantRole(incentivesPool.DISTRIBUTOR_ROLE(), address(reputation));
        incentivesPool.grantRole(incentivesPool.DEPOSITOR_ROLE(), address(membership));
        incentivesPool.grantRole(incentivesPool.DEPOSITOR_ROLE(), address(penalty));
    }

    function _configureAdminRoles(
        StakingContract staking,
        ReferralSystem referral,
        MembershipSystem membership,
        PenaltySystem penalty,
        EventRewards eventRewards,
        EducatorBonuses educatorBonuses,
        RecruiterBonuses recruiterBonuses,
        TalentBonuses talentBonuses,
        CommissionSystem commission,
        ReputationBonuses reputation,
        address protocolAdmin
    ) internal {
        staking.grantRole(staking.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        staking.grantRole(staking.ADMIN_ROLE(), protocolAdmin);

        referral.grantRole(referral.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        referral.grantRole(referral.ADMIN_ROLE(), protocolAdmin);

        membership.grantRole(membership.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        membership.grantRole(membership.ADMIN_ROLE(), protocolAdmin);

        penalty.grantRole(penalty.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        penalty.grantRole(penalty.ADMIN_ROLE(), protocolAdmin);
        penalty.grantRole(penalty.ENFORCER_ROLE(), protocolAdmin);

        eventRewards.grantRole(eventRewards.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        eventRewards.grantRole(eventRewards.ADMIN_ROLE(), protocolAdmin);
        eventRewards.grantRole(eventRewards.ENFORCER_ROLE(), protocolAdmin);

        educatorBonuses.grantRole(educatorBonuses.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        educatorBonuses.grantRole(educatorBonuses.ADMIN_ROLE(), protocolAdmin);
        educatorBonuses.grantRole(educatorBonuses.ENFORCER_ROLE(), protocolAdmin);

        recruiterBonuses.grantRole(recruiterBonuses.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        recruiterBonuses.grantRole(recruiterBonuses.ADMIN_ROLE(), protocolAdmin);
        recruiterBonuses.grantRole(recruiterBonuses.ENFORCER_ROLE(), protocolAdmin);

        talentBonuses.grantRole(talentBonuses.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        talentBonuses.grantRole(talentBonuses.ADMIN_ROLE(), protocolAdmin);
        talentBonuses.grantRole(talentBonuses.ENFORCER_ROLE(), protocolAdmin);

        commission.grantRole(commission.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        reputation.grantRole(reputation.DEFAULT_ADMIN_ROLE(), protocolAdmin);
        reputation.grantRole(reputation.ADMIN_ROLE(), protocolAdmin);
        reputation.grantRole(reputation.ENFORCER_ROLE(), protocolAdmin);
    }

    struct Deployment {
        address token;
        address incentivesPool;
        address staking;
        address referral;
        address membership;
        address penalty;
        address eventRewards;
        address educatorBonuses;
        address recruiterBonuses;
        address talentBonuses;
        address commission;
        address reputation;
        address presale;
    }
}
