// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IApeCoinStaking} from "./IApeCoinStaking.sol";

interface IApeBlendr { 
    struct ApeDraw {
        address winner;
        uint256 apeCoinAward;
        bool isFinalized;
        uint256 blockNumberRequested;
        uint256 blockNumberSettled;
    }

    struct ApeBlendrConfig {
        address apeCoin;
        address apeCoinStaking;
        address apeBlendrFeeReceiver;
        uint256 apeBlendrFeeBps;
        uint256 maxApeCoinStake;
        uint256 earlyExitFeeBps;
        uint256 epochSeconds;
        uint256 epochStartedAt;
    }

    struct ChainlinkVRFConfig {
        uint64 subscriptionId;
        bytes32 keyHash;
        uint32 callbackGasLimit;
        uint16 requestConfirmations;
        uint32 numWords;
        address vrfCordinator;
    }

    function getApeCoinStake() external view returns (IApeCoinStaking.DashboardStake memory);
    function epochEndAt() external view returns (uint256);
    function hasEpochEnded() external view returns (bool);
    function getCurrentTime() external view returns (uint256);
    function enterApeBlendr(uint256 amount) external;
    function exitApeBlendr(uint256 amount) external;
    function startApeCoinAwardingProcess() external;
    function handleFailedPrizeDraw(uint256 requestId) external;
    function updateApeBlendrFeeBps(uint256 newApeBlendrFeeBps) external;
    function updateApeBlendrFeeReceiver(address newApeBlendrFeeReceiver) external;
}