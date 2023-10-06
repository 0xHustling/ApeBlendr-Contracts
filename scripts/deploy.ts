import { ethers } from "hardhat";

async function main() {
  const apeBlendr = await ethers.deployContract("ApeBlendr", [
    process.env.APE_COIN_ADDRESS,
    process.env.APE_COIN_STAKING_ADDRESS,
    process.env.APE_BLENDR_FEE_BPS,
    process.env.EPOCH_SECONDS,
    process.env.EPOCH_STARTED_AT,
    process.env.SUBSCRIPTION_ID,
    process.env.KEY_HASH,
    process.env.CALLBACK_GAS_LIMIT,
    process.env.VRF_REQUEST_CONFIRMATIONS,
    process.env.NUM_WORDS,
    process.env.VRF_COORDINATOR,
  ]);

  await apeBlendr.waitForDeployment();

  console.log(
    `ApeBlendr deployed to: https://goerli.etherscan.io/address/${await apeBlendr.getAddress()}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
