import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

const SUBSCRIPTION_ID = "0";
const KEY_HASH =
  "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c";
const CALLBACK_GAS_LIMIT = "2400000";
const VRF_REQUEST_CONFIRMATIONS = "1";
const NUM_WORDS = "1";
const EPOCH_SECONDS = "3600";
const EPOCH_STARTED_AT = Math.floor(new Date().getTime() / 1000);
const APE_BLENDR_FEE_BPS = "500";
const APE_COIN_ADDRESS = "0x328507DC29C95c170B56a1b3A758eB7a9E73455c";
const APE_COIN_STAKING_ADDRESS = "0x146FD8C08baf234e3566C0c694eDad4833403C6b";
const APE_BLENDR_FEE_RECEIVER = "0xb023BDe368CaeE4dF312a21Cbe535800aD195608";
const MAX_APE_COIN_STAKE = "100000000000000000000000";
const EARLY_EXIT_FEE_BPS = "1000";

//TODO:: Add 100 % Test coverage
describe("ApeBlendr Tests", () => {
  const deployedContracts = async () => {
    const mockVRFCoordinator = await ethers.deployContract(
      "MockVRFCoordinator"
    );
    await mockVRFCoordinator.waitForDeployment();

    const apeCoin = await ethers.getContractAt("SimpleERC20", APE_COIN_ADDRESS);

    const ApeBlendr = await ethers.getContractFactory("ApeBlendr");
    const apeBlendr = await ApeBlendr.deploy(
      [
        APE_COIN_ADDRESS,
        APE_COIN_STAKING_ADDRESS,
        APE_BLENDR_FEE_RECEIVER,
        APE_BLENDR_FEE_BPS,
        MAX_APE_COIN_STAKE,
        EARLY_EXIT_FEE_BPS,
        EPOCH_SECONDS,
        EPOCH_STARTED_AT,
      ] as any,
      [
        SUBSCRIPTION_ID,
        KEY_HASH,
        CALLBACK_GAS_LIMIT,
        VRF_REQUEST_CONFIRMATIONS,
        NUM_WORDS,
        mockVRFCoordinator.getAddress(),
      ] as any
    );
    await apeBlendr.waitForDeployment();

    return {
      apeCoin,
      apeBlendr,
      mockVRFCoordinator,
    };
  };

  it("should successfully deploy ApeBlendr with correct configuration", async () => {
    const { apeBlendr } = await loadFixture(deployedContracts);

    const apeCoinAddress = await apeBlendr.apeCoin();
    const apeCoinStaking = await apeBlendr.apeCoinStaking();
    const apeBlendrFeeBps = await apeBlendr.apeBlendrFeeBps();
    const epochSeconds = await apeBlendr.epochSeconds();
    const epochStartedAt = await apeBlendr.epochStartedAt();

    expect(apeCoinAddress).to.equal(APE_COIN_ADDRESS);
    expect(apeCoinStaking).to.equal(APE_COIN_STAKING_ADDRESS);
    expect(apeBlendrFeeBps).to.equal(APE_BLENDR_FEE_BPS);
    expect(epochSeconds).to.equal(EPOCH_SECONDS);
    expect(epochStartedAt).to.equal(EPOCH_STARTED_AT);
  });

  it("should successfully deposit $APE to ApeBlendr contract", async () => {
    const { apeCoin, apeBlendr } = await loadFixture(deployedContracts);

    const accounts = await ethers.getSigners();

    await apeCoin
      .connect(accounts[0])
      .mint(accounts[0].getAddress(), "100000000000000000000000");
    await apeCoin
      .connect(accounts[0])
      .approve(apeBlendr.getAddress(), ethers.MaxUint256);

    await apeBlendr
      .connect(accounts[0])
      .enterApeBlendr("10000000000000000000000");
  });

  it("should successfully withdraw $APE to ApeBlendr contract", async () => {
    const { apeCoin, apeBlendr } = await loadFixture(deployedContracts);

    const accounts = await ethers.getSigners();

    await apeCoin
      .connect(accounts[0])
      .mint(accounts[0].getAddress(), "100000000000000000000000");
    await apeCoin
      .connect(accounts[0])
      .approve(apeBlendr.getAddress(), ethers.MaxUint256);

    await apeBlendr
      .connect(accounts[0])
      .enterApeBlendr("10000000000000000000000");
    await apeBlendr
      .connect(accounts[0])
      .exitApeBlendr("10000000000000000000000");
  });

  it("should not be able to start awarding process when epoch has not ended", async () => {
    const { apeCoin, apeBlendr } = await loadFixture(deployedContracts);
    const accounts = await ethers.getSigners();

    for (let i = 0; i < 10; i++) {
      await apeCoin
        .connect(accounts[i])
        .mint(accounts[i].getAddress(), "100000000000000000000000");
      await apeCoin
        .connect(accounts[i])
        .approve(apeBlendr.getAddress(), ethers.MaxUint256);

      await apeBlendr
        .connect(accounts[i])
        .enterApeBlendr("10000000000000000000000");
    }

    await expect(
      apeBlendr.connect(accounts[11]).startApeCoinAwardingProcess()
    ).to.be.revertedWithCustomError(apeBlendr, "CurrentEpochHasNotEnded");
  });

  it("should be able to start awarding process when epoch has ended", async () => {
    const { apeCoin, apeBlendr } = await loadFixture(deployedContracts);
    const accounts = await ethers.getSigners();

    for (let i = 0; i < 10; i++) {
      await apeCoin
        .connect(accounts[i])
        .mint(accounts[i].getAddress(), "100000000000000000000000");
      await apeCoin
        .connect(accounts[i])
        .approve(apeBlendr.getAddress(), ethers.MaxUint256);

      await apeBlendr
        .connect(accounts[i])
        .enterApeBlendr("10000000000000000000000");
    }

    await time.increase(2 * 3600);

    await expect(
      apeBlendr.connect(accounts[11]).startApeCoinAwardingProcess()
    ).to.be.emit(apeBlendr, "AwardingStarted");
  });

  it("should be able to finish awarding process and and award 1 winner", async () => {
    const { apeCoin, apeBlendr, mockVRFCoordinator } = await loadFixture(
      deployedContracts
    );
    const accounts = await ethers.getSigners();

    for (let i = 0; i < 10; i++) {
      await apeCoin
        .connect(accounts[i])
        .mint(accounts[i].getAddress(), "100000000000000000000000");
      await apeCoin
        .connect(accounts[i])
        .approve(apeBlendr.getAddress(), ethers.MaxUint256);

      await apeBlendr
        .connect(accounts[i])
        .enterApeBlendr("10000000000000000000000");
    }

    await time.increase(2 * 3600);

    await expect(
      apeBlendr.connect(accounts[11]).startApeCoinAwardingProcess()
    ).to.be.emit(apeBlendr, "AwardingStarted");

    await mockVRFCoordinator
      .connect(accounts[11])
      .triggerRawFulfillRandomWords();
  });
}).timeout(72000);