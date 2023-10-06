// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {VRFv2Consumer} from "./chainlink/VRFv2Consumer.sol";
import {SortitionSumTreeFactory} from "./lib/SortitionSumTreeFactory.sol";
import {UniformRandomNumber} from "./lib/UniformRandomNumber.sol";

import {IApeCoinStaking} from "./interfaces/IApeCoinStaking.sol";
import {IApeBlendr} from "./interfaces/IApeBlendr.sol";

/**
 * @title ApeBlendr
 * @author 0xHustling
 * @dev ApeBlendr is a no-loss savings game inspired by PoolTogether and built on top of the ApeCoin protocol.
 * @dev Currently, ApeCoin provides a staking program with juicy yields, so why not gamify it?
 */
contract ApeBlendr is IApeBlendr, ERC20, VRFv2Consumer, Ownable {
    using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;

    /* ========== STATE VARIABLES ========== */

    address public immutable apeCoin;
    address public immutable apeCoinStaking;
    address public apeBlendrFeeReceiver;

    uint256 public apeBlendrFeeBps;
    uint256 public maxApeCoinStake;
    uint256 public earlyExitFeeBps;
    uint256 public epochSeconds;
    uint256 public epochStartedAt;
    uint256 public totalPrizeDraws;

    bool public awardingInProgress;

    // Mapping for storing ApeDraw details by request ID.
    mapping(uint256 => ApeDraw) public apeDraws;

    // Mapping for storing latest deposit timestamp for address
    mapping(address => uint256) public lastDepositTimestamp;

    /* ========== CONSTANTS ========== */

    bytes32 private constant TREE_KEY = keccak256("ApeBlendr/ApeCoin");
    uint256 private constant MAX_TREE_LEAVES = 5;
    uint256 private constant APE_COIN_PRECISION = 1e18;
    uint256 private constant VRF_MAX_BLOCKS_WAIT_TIME = 7200;
    uint256 private constant MAX_FEE_BPS = 1000;
    uint256 private constant MIN_APE_COIN_STAKE = 10000 * 1e18;

    // Internal data structure for managing SortitionSumTree.
    SortitionSumTreeFactory.SortitionSumTrees internal sortitionSumTrees;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Constructor to initialize the ApeBlendr contract.
     * @param apeBlendrConfig ApeBlendr configuration settings.
     * @param chainlinkConfig Chainlink VRF configuration settings.
     */
    constructor(ApeBlendrConfig memory apeBlendrConfig, ChainlinkVRFConfig memory chainlinkConfig)
        ERC20("ApeBlendr", "APEb")
        Ownable(msg.sender)
        VRFv2Consumer(
            chainlinkConfig.subscriptionId,
            chainlinkConfig.keyHash,
            chainlinkConfig.callbackGasLimit,
            chainlinkConfig.requestConfirmations,
            chainlinkConfig.numWords,
            chainlinkConfig.vrfCordinator
        )
    {
        // Initialize contract state and create a SortitionSumTree.
        apeCoin = apeBlendrConfig.apeCoin;
        apeCoinStaking = apeBlendrConfig.apeCoinStaking;
        apeBlendrFeeReceiver = apeBlendrConfig.apeBlendrFeeReceiver;
        apeBlendrFeeBps = apeBlendrConfig.apeBlendrFeeBps;
        maxApeCoinStake = apeBlendrConfig.maxApeCoinStake;
        earlyExitFeeBps = apeBlendrConfig.earlyExitFeeBps;
        epochSeconds = apeBlendrConfig.epochSeconds;
        epochStartedAt = apeBlendrConfig.epochStartedAt;

        sortitionSumTrees.createTree(TREE_KEY, MAX_TREE_LEAVES);
        IERC20(apeCoin).approve(apeCoinStaking, type(uint256).max);
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Get ApeCoin staking information for this contract.
     * @return A struct containing ApeCoin staking details.
     */
    function getApeCoinStake() public view returns (IApeCoinStaking.DashboardStake memory) {
        return IApeCoinStaking(apeCoinStaking).getApeCoinStake(address(this));
    }

    /**
     * @dev Get the timestamp when the current epoch ends.
     * @return The timestamp of the current epoch's end.
     */
    function epochEndAt() public view returns (uint256) {
        return epochStartedAt + epochSeconds;
    }

    /**
     * @dev Check if the current epoch has ended.
     * @return True if the epoch has ended, false otherwise.
     */
    function hasEpochEnded() external view returns (bool) {
        return block.timestamp >= epochEndAt();
    }

    /**
     * @dev Get the current block timestamp.
     * @return The current timestamp.
     */
    function getCurrentTime() public view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Get the award for the current prize draw.
     * @return awardForCurrentDraw The award for the current prize draw.
     */
    function getAwardForCurrentDraw() external view returns (uint256 awardForCurrentDraw) {
        // Get ApeCoin stake infro from ApeCoin Staking contract
        IApeCoinStaking.DashboardStake memory apeStakeInfo = getApeCoinStake();

        // Get the total supply of $APEb
        uint256 totalSupply = totalSupply();

        // Get the total $APE balance delegated to the ApeBlendr -> deposited + unclaimed
        uint256 totalApeCoinBalance = apeStakeInfo.deposited + apeStakeInfo.unclaimed;

        // Calculate award for current draw
        awardForCurrentDraw = totalApeCoinBalance > totalSupply ? (totalApeCoinBalance - totalSupply) : 0;
    }

    /**
     * @dev Calculate the timestamp of the start of the next epoch.
     * @param currentTime The current time.
     * @return The timestamp of the next epoch's start.
     */
    function _calculateNextEpochStartTime(uint256 currentTime) internal view returns (uint256) {
        uint256 elapsedEpochs = (currentTime - epochStartedAt) / epochSeconds;
        return epochStartedAt + (elapsedEpochs * epochSeconds);
    }

    /**
     * @dev Check if the current epoch has not ended and revert if it has.
     */
    function _checkEpochHasNotEnded() internal view {
        if (getCurrentTime() > epochEndAt()) {
            revert CurrentEpochHasEnded();
        }
    }

    /**
     * @dev Check if the current epoch has ended and revert if it hasn't.
     */
    function _checkEpochHasEnded() internal view {
        if (getCurrentTime() < epochEndAt()) {
            revert CurrentEpochHasNotEnded();
        }
    }

    /**
     * @dev Check if an awarding process is in progress and revert if it is.
     */
    function _checkAwardingInProgress() internal view {
        if (awardingInProgress) revert AwardingInProgress();
    }

    /**
     * @dev Check if an awarding process is in progress and revert if it is.
     * @param player The player's address for whom the deposit timestamp is being checked.
     */
    function _checkIsEarlyExit(address player) internal view returns (bool isEarlyExit) {
        uint256 lastDeposit = lastDepositTimestamp[player];
        (lastDeposit + epochSeconds) > getCurrentTime() ? isEarlyExit = true : isEarlyExit = false;
    }

    /**
     * @dev Check if the player exceeds the max $APE coin stake.
     * @param player The player's address for whom the max stake is being checked.
     * @param amount The player's amount for whom the max stake is being checked.
     */
    function _checkMaxApeCoinStake(address player, uint256 amount) internal view {
        if ((amount + balanceOf(player)) > maxApeCoinStake) revert MaxApeCoinStakeExceeded();
    }

    /**
     * @dev Calculate the ApeBlendr fee based on a prize amount and fee basis points (BPS).
     * @param _prizeAmount The prize amount.
     * @param _apeBlendrFeeBps The fee in basis points.
     * @return apeBlendrFee The calculated fee amount.
     */
    function _calculateApeBlendrFee(uint256 _prizeAmount, uint256 _apeBlendrFeeBps)
        internal
        pure
        returns (uint256 apeBlendrFee)
    {
        apeBlendrFee = (_apeBlendrFeeBps * _prizeAmount) / 10000;
    }

    /**
     * @dev Draw a winner based on a random number.
     * @param randomWord The random number used for the draw.
     * @return winner The address of the winner.
     */
    function _drawWinner(uint256 randomWord) internal view returns (address winner) {
        uint256 bound = totalSupply();
        if (bound == 0) {
            winner = address(0);
        } else {
            uint256 token = UniformRandomNumber.uniform(randomWord, bound);
            winner = address(uint160(uint256(sortitionSumTrees.draw(TREE_KEY, token))));
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allow users to enter the ApeBlendr by staking $APE coin.
     * @param amount The amount of $APE coin to stake.
     */
    function enterApeBlendr(uint256 amount) external {
        _checkEpochHasNotEnded();
        _checkAwardingInProgress();
        _updateLastDepositTimestampForAddress(msg.sender);
        _checkMaxApeCoinStake(msg.sender, amount);

        _mint(msg.sender, amount);

        IERC20(apeCoin).transferFrom(msg.sender, address(this), amount);

        IApeCoinStaking(apeCoinStaking).depositSelfApeCoin(amount);

        emit ApeBlendrEntered(msg.sender, amount);
    }

    /**
     * @dev Allow users to exit the ApeBlendr and withdraw their staked tokens.
     * @param amount The amount of $APE coin to withdraw.
     */
    function exitApeBlendr(uint256 amount) external {
        _checkAwardingInProgress();

        bool isEarlyExit = _checkIsEarlyExit(msg.sender);
        uint256 amountToWithdraw;

        isEarlyExit ? amountToWithdraw = (((10000 - earlyExitFeeBps) * amount) / 10000) : amountToWithdraw = amount;
        _burn(msg.sender, amount);

        IApeCoinStaking(apeCoinStaking).withdrawApeCoin(amountToWithdraw, msg.sender);

        emit ApeBlendrExited(msg.sender, amountToWithdraw);
    }

    /**
     * @dev Start the ApeCoin awarding process for the current epoch.
     */
    function startApeCoinAwardingProcess() external {
        // Check if current epoch has ended
        _checkEpochHasEnded();

        // Check if awarding is not already in progress
        _checkAwardingInProgress();

        // Flag awarding in progress
        awardingInProgress = true;

        // Get ApeCoin stake infro from ApeCoin Staking contract
        IApeCoinStaking.DashboardStake memory apeStakeInfo = getApeCoinStake();

        // Get the total supply of $APEb
        uint256 totalSupply = totalSupply();

        // Get the total $APE balance delegated to the ApeBlendr -> deposited + unclaimed
        uint256 totalApeCoinBalance = apeStakeInfo.deposited + apeStakeInfo.unclaimed;

        // Calculate award for current draw
        uint256 awardForCurrentDraw = totalApeCoinBalance > totalSupply ? (totalApeCoinBalance - totalSupply) : 0;

        // Initiate awarding only in case there is prize to be distributed
        if (awardForCurrentDraw > 0) {
            // Request random number from Chainlink VRF
            uint256 requestId = requestRandomWords();

            // Get the amount to be harvested from ApeCoin Staking
            uint256 amountToHarvest = apeStakeInfo.unclaimed;

            // Save the award for the current draw in storage
            apeDraws[requestId].apeCoinAward = awardForCurrentDraw;

            // Save the block.number when the request was initiated
            apeDraws[requestId].blockNumberRequested = block.number;

            // Check if award is more than 1 $APE
            if (amountToHarvest >= 1 * (APE_COIN_PRECISION)) {
                // Harvest the accrued $APE for the period
                IApeCoinStaking(apeCoinStaking).claimSelfApeCoin();

                // Deposit back the accrued $APE
                IApeCoinStaking(apeCoinStaking).depositSelfApeCoin(amountToHarvest);
            }

            // Check if award is less than 1 $APE
            if (amountToHarvest < 1 * (APE_COIN_PRECISION)) {
                // Harvest the accrued $APE for the period
                IApeCoinStaking(apeCoinStaking).claimSelfApeCoin();

                // As the ApeCoin staking contract does not allow for staking less than 1 $APE
                // we have to withdraw exactly the remaining difference, so we can stake back
                IApeCoinStaking(apeCoinStaking).withdrawApeCoin(
                    (1 * (APE_COIN_PRECISION) - amountToHarvest), address(this)
                );

                // Deposit back exactly 1 $APE
                IApeCoinStaking(apeCoinStaking).depositSelfApeCoin(1 * (APE_COIN_PRECISION));
            }

            emit AwardingStarted(requestId, awardForCurrentDraw);
        } else {
            // Finalize the epoch and initiate a new one
            _finalizeEpoch();

            emit NoAwardForCurrentEpoch(totalPrizeDraws);
        }
    }

    /**
     * @dev Handle a failed VRF request for a specific draw.
     * @param requestId The request ID for the failed draw.
     */
    function handleFailedPrizeDraw(uint256 requestId) external {
        ApeDraw storage failedApeDraw = apeDraws[requestId];

        // Check if draw is finalized. Revert if true.
        if (failedApeDraw.isFinalized) revert DrawIsFinalized();

        // Check if awarding is not in progress. Revert if true.
        if (!awardingInProgress) revert AwardingNotInProgress();

        // Check that more than 24hrs have passed since VRF request. According to
        // Chainlink, if a VRF request hangs for more than 24hrs, it is considered as failed.
        if (block.number < failedApeDraw.blockNumberRequested + VRF_MAX_BLOCKS_WAIT_TIME) {
            revert VRFRequestStillPending();
        }

        // Mark the ApeDraw as finalized.
        failedApeDraw.isFinalized = true;

        // Mark the block at which the draw is settled.
        failedApeDraw.blockNumberSettled = block.number;

        // Finalize the current epoch and initiate a new one
        _finalizeEpoch();

        emit AwardingPostponed(requestId, (failedApeDraw.apeCoinAward));
    }

    /**
     * @dev Updates the ApeBlendr fee receiver address. Only the contract owner can call this function.
     * @param newApeBlendrFeeReceiver The new ApeBlendr fee receiver address. It cannot be the zero address.
     */
    function updateApeBlendrFeeReceiver(address newApeBlendrFeeReceiver) external onlyOwner {
        if (newApeBlendrFeeReceiver == address(0)) revert ZeroAddress();

        apeBlendrFeeReceiver = newApeBlendrFeeReceiver;

        emit ApeBlendrFeeReceiverUpdated(newApeBlendrFeeReceiver);
    }

    /**
     * @dev Updates the ApeBlendr fee in basis points (Bps). Only the contract owner can call this function.
     * @param newApeBlendrFeeBps The new ApeBlendr fee in basis points (Bps). It must not exceed the maximum fee Bps.
     */
    function updateApeBlendrFeeBps(uint256 newApeBlendrFeeBps) external onlyOwner {
        if (newApeBlendrFeeBps > MAX_FEE_BPS) revert ApeBlendrFeeTooBig();

        apeBlendrFeeBps = newApeBlendrFeeBps;

        emit ApeBlendrFeeBpsUpdated(newApeBlendrFeeBps);
    }

    /**
     * @dev Updates the ApeBlendr fee in basis points (Bps). Only the contract owner can call this function.
     * @param newMaxApeCoinStake The new ApeBlendr fee in basis points (Bps). It must not exceed the maximum fee Bps.
     */
    function updateMaxApeCoinStake(uint256 newMaxApeCoinStake) external onlyOwner {
        if (newMaxApeCoinStake < MIN_APE_COIN_STAKE) revert MaxApeCoinStakeTooLow();

        maxApeCoinStake = newMaxApeCoinStake;

        emit ApeBlendrFeeBpsUpdated(newMaxApeCoinStake);
    }

    /**
     * @dev Request random words from Chainlink VRF for settling an ApeCoin award.
     * @return _userRequestId The request ID for the VRF request.
     */
    function requestRandomWords() internal returns (uint256 _userRequestId) {
        _userRequestId =
            COORDINATOR.requestRandomWords(keyHash, s_subscriptionId, requestConfirmations, callbackGasLimit, numWords);
    }

    /**
     * @dev Fulfill the random words request and settle the ApeCoin award.
     * @param requestId The request ID for the VRF request.
     * @param randomWords An array of random words generated by Chainlink VRF.
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        _settleApeCoinAwardForDraw(requestId, randomWords[0]);
    }

    /**
     * @dev Updates the latest deposit timestamp for a specific player's address.
     * @param player The player's address for whom the deposit timestamp is being updated.
     */
    function _updateLastDepositTimestampForAddress(address player) internal {
        lastDepositTimestamp[player] = block.timestamp;
    }

    /**
     * @dev Settle the ApeCoin award for a specific draw request.
     * @param requestId The ID of the draw request.
     * @param randomWord The random word for the draw.
     */
    function _settleApeCoinAwardForDraw(uint256 requestId, uint256 randomWord) internal {
        ApeDraw storage apeDraw = apeDraws[requestId];

        apeDraw.winner = _drawWinner(randomWord);
        apeDraw.isFinalized = true;
        apeDraw.blockNumberSettled = block.number;

        uint256 apeBlendrFee = _calculateApeBlendrFee(apeDraw.apeCoinAward, apeBlendrFeeBps);

        ++totalPrizeDraws;

        _finalizeEpoch();

        if (apeDraw.winner != address(0) && apeDraw.apeCoinAward != 0) {
            _mint(apeDraw.winner, (apeDraw.apeCoinAward - apeBlendrFee));
            _mint(apeBlendrFeeReceiver, apeBlendrFee);
        }

        emit AwardingFinished(requestId, (apeDraw.apeCoinAward - apeBlendrFee), apeDraw.winner);
    }

    /**
     * @dev Finalize the current epoch and update contract state.
     */
    function _finalizeEpoch() internal {
        awardingInProgress = false;
        epochStartedAt = _calculateNextEpochStartTime(getCurrentTime());

        emit EpochEnded(epochStartedAt);
    }

    /**
     * @dev Override the internal token transfer update function to update the SortitionSumTree.
     * @param from The address sending tokens.
     * @param to The address receiving tokens.
     * @param amount The amount of tokens being transferred.
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        if (from == to) revert UnauthorizedTransfer();

        if (from != address(0)) {
            uint256 fromBalance = balanceOf(from) - amount;
            sortitionSumTrees.set(TREE_KEY, fromBalance, bytes32(uint256(uint160(from))));
        }

        if (to != address(0)) {
            uint256 toBalance = balanceOf(to) + amount;
            sortitionSumTrees.set(TREE_KEY, toBalance, bytes32(uint256(uint160(to))));
        }

        super._update(from, to, amount);
    }

    /* ========== EVENTS ========== */

    event ApeBlendrEntered(address player, uint256 amount);
    event ApeBlendrExited(address player, uint256 amount);
    event EpochEnded(uint256 newEpochStartedAt);
    event AwardingStarted(uint256 requestId, uint256 awardForDraw);
    event AwardingFinished(uint256 requestId, uint256 awardForDraw, address winner);
    event AwardingPostponed(uint256 requestId, uint256 postponedAwardForDraw);
    event NoAwardForCurrentEpoch(uint256 currentEpoch);
    event ApeBlendrFeeReceiverUpdated(address newApeBlendrFeeReceiver);
    event ApeBlendrFeeBpsUpdated(uint256 newApeBlendrFeeBps);
    event ApeBlendrMaxApeCoinStakeUpdated(uint256 newMaxApeCoinStake);

    /* ========== CUSTOM ERRORS ========== */

    error CurrentEpochHasEnded();
    error CurrentEpochHasNotEnded();
    error AwardingInProgress();
    error AwardingNotInProgress();
    error UnauthorizedTransfer();
    error VRFRequestStillPending();
    error DrawIsFinalized();
    error ZeroAddress();
    error ApeBlendrFeeTooBig();
    error MaxApeCoinStakeExceeded();
    error MaxApeCoinStakeTooLow();
}