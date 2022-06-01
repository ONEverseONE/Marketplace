const { expect } = require("chai");
const { ethers } = require("hardhat");
const { parseEther } = require("ethers/lib/utils");
const { constants } = require('@openzeppelin/test-helpers');

describe('★ ONEVERSE Marketplace Test Suite ★', async () =>{
  let owner, alice, bob, carol, creator, nft, token, market;
  before(async () =>{
    [owner, alice, bob, carol, creator] = await ethers.getSigners();
    const project = await ethers.getContractFactory('testNFT');
    nft = await project.deploy();
    const PaymentToken = await ethers.getContractFactory('Token');
    token = await PaymentToken.deploy();
    const marketplace = await ethers.getContractFactory('Collection');
    market = await marketplace.deploy(nft.address, token.address, creator.address, 200);

    await nft.connect(bob).mint(3);
    await nft.connect(alice).mint(3);
    await nft.connect(carol).mint(3);

    await nft.connect(alice).setApprovalForAll(market.address, true);
    await nft.connect(bob).setApprovalForAll(market.address, true);
    await nft.connect(carol).setApprovalForAll(market.address, true);

    await token.connect(alice).mint(parseEther('1000'));
    await token.connect(bob).mint(parseEther('1000'));
    await token.connect(carol).mint(parseEther('1000'));

    await token.connect(alice).approve(market.address, parseEther('10000'));
    await token.connect(bob).approve(market.address, parseEther('10000'));
    await token.connect(carol).approve(market.address, parseEther('10000'));
  });

  describe("Alice Lists a NFT in marketplace in direct Listing ▼", async () =>{
    it("Token Listed Event is captured", async () =>{
      await expect(market.connect(alice)['listToken(uint256,uint256)'](5, parseEther('100')))
          .to.emit(market, 'tokenListed')
          .withArgs(alice.address, 5, 1, parseEther('100'));
    });

    it("Direct Sales mapping gets updated", async () =>{
      let structVar = await market.directSales(5);
      expect(structVar[0]).to.eq(alice.address);
      expect(structVar[1]).to.eq(parseEther('100'));
    });
  });

  describe("Bob lists a NFT for Auction ▼", async () =>{
    it("Duration must be less than 14", async () =>{
      await expect(market.connect(bob)['listToken(uint256,uint256,uint256)']
      (3, parseEther('150'), ethers.BigNumber.from('1296000')))
          .to.be.revertedWith('Auction can\'t last more than 14 days')
    });

    it("Token Listed Event Captured", async () =>{
      await expect(market.connect(bob)['listToken(uint256,uint256,uint256)'](3, parseEther('150'),
          ethers.BigNumber.from('86400')))
          .to.emit(market, 'tokenListed')
          .withArgs(bob.address, 3, 2, parseEther('150'));
    });

    it("Auction Sales Mapping updated", async ()=>{
      let structVar = await market.auctionSales(3);
      expect(structVar[0]).to.eq(bob.address);
      expect(structVar[1]).to.eq(ethers.BigNumber.from('86400'));
      expect(structVar[2]).to.eq('0');
      expect(structVar[3]).to.eq(parseEther('150'));
      expect(structVar[4]).to.eq(constants.ZERO_ADDRESS);
    });
  });

  describe("Carol buys Token from MarketPlace(!Auction) ▼", async () =>{
    it("Token Bought Event Emitted", async () =>{
      await expect(market.connect(carol).buyToken(5, parseEther('120')))
          .to.emit(market, 'tokenBought')
          .withArgs(carol.address, 5);
    });

    it("Seller gets correct amount stored in `balance` after cutting dev fees and royalty fees", async () =>{
      expect(await market.balance(alice.address)).to.eq(parseEther('115.2'))
    });

    it('Direct Sales struct deleted', async () =>{
      let structVar = await market.directSales(5);
      expect(structVar[0]).to.eq(constants.ZERO_ADDRESS);
    });
  });

  describe("Auction Undergoes!! ▼", async () =>{
    it("Bob tries to buy gets reverted", async () =>{
      await expect(market.connect(bob).bidToken(3, parseEther('10')))
          .to.be.revertedWith('Can\'t buy own token')
    })

    it("Carol Bids but bids for less than highest bid", async () => {
      await expect(market.connect(carol).bidToken(3, parseEther('10')))
          .to.be.revertedWith('Bid higher');
    });

    it("Carol Bids successfully and Event captured", async () =>{
      await expect(market.connect(carol).bidToken(3, parseEther('150')))
          .to.emit(market, 'receivedBid')
          .withArgs(carol.address, 3, parseEther('150'));
    });

    it("Can't outbid self", async () =>{
      await expect(market.connect(carol).bidToken(3, parseEther('200')))
          .to.be.revertedWith('Can\'t bid twice');
    });

    it("Alice Overbids and She Auction Sales mapping gets updated accordingly", async () =>{
      await expect(market.connect(alice).bidToken(3, parseEther('200')))
          .to.emit(market, 'receivedBid')
          .withArgs(alice.address, 3, parseEther('200'));
      let structVar = await market.auctionSales(3);
      expect(structVar[4]).to.eq(alice.address);
      expect(structVar[3]).to.eq(parseEther('200'));
    });

    it("Alice tries to retrieve before Auction ends should be reverted", async () =>{
      await expect(market.connect(alice).retrieveToken(3)).to.be.revertedWith('Auction not over');
    });

    it("Time's up and now Alice can retrieve token and Token Bought Event Emitted", async () =>{
      await network.provider.send("evm_increaseTime", [24*3600]);
      await expect(market.connect(alice).retrieveToken(3)).to.emit
      (market, 'tokenBought').withArgs(alice.address, 3);
    });

    it("Listed Mapping gets deleted", async () =>{
      expect(await market.listed(3)).to.eq('0');
    });

    it("Bob's Balance Mapping gets updated", async () =>{
      expect(await market.balance(bob.address)).to.eq(parseEther('192'));
    });
  });

  describe("Carol lists and then de-lists a token ▼", async () =>{
    it('Emits a event', async () =>{
      await expect(market.connect(carol)['listToken(uint256,uint256,uint256)'](8, parseEther('175'),
          ethers.BigNumber.from('172800')))
          .to.emit(market, 'tokenListed')
          .withArgs(carol.address, 8, 2, parseEther('175'));
    });

    it("De-lists as no one bids and emits a event", async () =>{
      await expect(market.connect(carol).delistToken([8]))
          .to.emit(market, 'tokenDeListed')
          .withArgs(8, 2);
    });
  });

  describe("Carol Lists again and changing royalty % and Fee% after listing ▼", async () =>{
    it("Listing Event captured ownership transferred", async () =>{
      await expect(market.connect(carol)['listToken(uint256,uint256,uint256)'](8, parseEther('175'),
          ethers.BigNumber.from('172800')))
          .to.emit(market, 'tokenListed')
          .withArgs(carol.address, 8, 2, parseEther('175'));
      expect(await nft.ownerOf(8)).to.eq(market.address);
    });

    it("Alice places first Bid", async () =>{
      await expect(market.connect(alice).bidToken(8, parseEther('200')))
          .to.emit(market, 'receivedBid')
          .withArgs(alice.address, 8, parseEther('200'));
      let structVar = await market.auctionSales(8);
      expect(structVar[4]).to.eq(alice.address);
    });

    it("Carol De-lists and highest Bidder is returned amount", async () =>{
      await market.connect(carol).delistToken([8]);
      expect(await token.balanceOf(alice.address)).to.eq(parseEther('600'));
    });

    it("Carol lists again", async () =>{
      await expect(market.connect(carol)['listToken(uint256,uint256,uint256)'](8, parseEther('175'),
          ethers.BigNumber.from('172800')))
          .to.emit(market, 'tokenListed')
          .withArgs(carol.address, 8, 2, parseEther('175'));
      expect(await nft.ownerOf(8)).to.eq(market.address);
    });

    it("Royalty and Dev Fees % changed", async () =>{
      await market.setRoyaltyPercentage(300);
      await market.setFee(300);
    });

    it("Bob buys the NFT after out-biding Alice", async () =>{
      await expect(market.connect(bob).bidToken(8, parseEther('190')))
          .to.emit(market, 'receivedBid')
          .withArgs(bob.address, 8, parseEther('190'));
      await network.provider.send("evm_increaseTime", [2*24*3600]);
      await expect(market.connect(bob).retrieveToken(8)).to.emit
      (market, 'tokenBought').withArgs(bob.address, 8);
      expect(await nft.ownerOf(8)).to.eq(bob.address);
    });

    it("Balance Of Carol gets updated", async () =>{
      expect(await market.balance(carol.address)).to.eq(parseEther('328.6'));
    })

    it("Royalty fees get updated", async () =>{
      expect(await market.royaltyBalance()).to.eq(parseEther('12.1'));
    });
  });

  describe("Retrieving balance, fees, royalties", async () =>{
    it("Alice, Bob and Carol retrieve respective balances", async () =>{
      await market.connect(alice).retrieveBalance();
      await market.connect(bob).retrieveBalance();
      await market.connect(carol).retrieveBalance();

      expect(await token.balanceOf(alice.address)).to.eq(parseEther('915.2'));
      expect(await token.balanceOf(bob.address)).to.eq(parseEther('1002'));
      expect(await token.balanceOf(carol.address)).to.eq(parseEther('1058.6'));
    });

    it("Royalty Fees received", async () =>{
      await market.connect(creator).retrieveRoyalty();
      expect(await token.balanceOf(creator.address)).to.eq(parseEther('12.1'));
    });

    it("Dev Fees received", async ()=>{
      await market.retrieveFee();
      expect(await token.balanceOf(owner.address)).to.eq(parseEther('12.1'));
    })
  });
});