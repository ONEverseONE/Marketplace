// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { parseEther } = require("ethers/lib/utils");
const { ethers } = require("hardhat");
const hre = require("hardhat");

async function main() {

  // We get the contract to deploy
  console.log("Deploying ERC20 token");
  const Token = await hre.ethers.getContractFactory("ERC20Token");
  const token = await Token.deploy();
  console.log("Token deployed at:", token.address);
  console.log("Minting 1000 tokens to owner address");
  await token.mint(parseEther('1000'));
  console.log("Tokens minted");
  await hre.run("verify:verify", {
    address: token.address,
    contract: "contracts/ERC20Token.sol:ERC20Token",
    network:"harmonytestnet"
  });
  console.log("Deploying NFT contract")
  const NFT = await hre.ethers.getContractFactory("NFT");
  const nft = await NFT.deploy();
  console.log("NFT contract deployed at:",nft.address);
  console.log("Minting 10 tokens to owner address");
  await nft.mint(10);
  console.log("Tokens minted");
  await hre.run("verify:verify", {
    address: nft.address,
    contract: "contracts/NFT.sol:NFT",
    network:"harmonytestnet"
  });
  console.log("Deploying marketplace contract");
  const Greeter = await hre.ethers.getContractFactory("Collection");
  const greeter = await Greeter.deploy(token.address);
  await greeter.deployed();
  console.log("Marketplace deployed to:", greeter.address);
  await hre.run("verify:verify", {
    address: greeter.address,
    constructorArguments: [token.address],
    contract: "contracts/Collection.sol:Collection",
    network:"harmonytestnet"
  });
  console.log("Setting a market for our NFT contract");
  greeter.setMarketplace(nft.address,ethers.constants.AddressZero,0);
  console.log("Marketplace set and ready to use");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
