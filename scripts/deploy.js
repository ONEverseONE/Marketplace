// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const Token = await hre.ethers.getContractFactory("TestToken");
  const token = await Token.deploy();
  const Greeter = await hre.ethers.getContractFactory("Collection");
  const greeter = await Greeter.deploy("0x701d1907fd9Ed5A1B4d6f005D602C723F9fD47fa",token.address,"0xE2Ccad70370800c5319261Be716B41732F802f62",0);

  await greeter.deployed();
  console.log("Token Address:",token.address);
  console.log("Collection deployed to:", greeter.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
