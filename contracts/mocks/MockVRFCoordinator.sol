//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

contract MockVRFCoordinator {
    uint256 internal counter = 1;
    uint256 internal lastRequestId;
    uint256[1] internal lastRandomWords;
    VRFConsumerBaseV2 consumer;

    constructor() {}

    function requestRandomWords(bytes32, uint64, uint16, uint32, uint32) external returns (uint256 requestId) {
        consumer = VRFConsumerBaseV2(msg.sender);
        lastRandomWords[0] = uint256(keccak256(abi.encode(block.prevrandao, block.timestamp, counter)));
        counter += 1;
        requestId = uint256(keccak256(abi.encode(block.prevrandao, block.timestamp, counter)));
        lastRequestId = requestId;
    }

    function triggerRawFulfillRandomWords() external {
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = lastRandomWords[0];
        consumer.rawFulfillRandomWords(lastRequestId, randomWords);
        lastRequestId = 0;
    }
}
