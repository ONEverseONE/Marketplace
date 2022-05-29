//SPDX-License-Identifier: UNLICENSED

/// @title Simple Marketplace Collection contract
/// @author Ace
/// @notice This contract represents a single collection in a custodial marketplace
/// @dev Use this contract with factory to create a complete marketplace

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Collection is Ownable{

    IERC721 NFT;
    IERC20 PaymentToken;

    struct directListing{
        address owner;
        uint price;
    }

    struct auctionListing{
        address owner;
        uint duration;
        uint timeEnd;
        uint highestBid;
        address highestBidder;
    }

    uint public FEE = 200; //2% since we divide by 10_000
    uint public royaltyPercentage; 
    uint public FEEBalance;
    uint public differentialAmount = 10 ether;
    mapping(address=>uint) public balance;
    mapping(uint=>uint) public listed; //0 - not, 1 = direct, 2 = auction

    mapping(uint=>directListing) public directSales;
    mapping(uint=>auctionListing) public auctionSales;

    event tokenListed(address indexed owner,uint indexed tokenId,uint8 listingType,uint price);
    event tokenBought(address indexed buyer,uint indexed tokenId);
    event receivedBid(address indexed bidder,uint indexed tokenId,uint amount);
    event tokenDeListed(uint indexed tokenId,uint8 listingType);

    constructor(address _collection,address _token) {
        NFT = IERC721(_collection);
        PaymentToken = IERC20(_token);
    }
   

    //@notice direct listing
    function listToken(uint tokenId,uint price) external {
        require(NFT.ownerOf(tokenId) == msg.sender,"Not owner");
        require(price != 0,"Can't sell for free");
        NFT.transferFrom(msg.sender, address(this), tokenId);
        listed[tokenId] = 1;
        directSales[tokenId] = directListing(msg.sender,price);
        emit tokenListed(msg.sender, tokenId,1,price);
    }
    
    //@notice auction listing
    function listToken(uint tokenId,uint price,uint duration) external {
        require(NFT.ownerOf(tokenId) == msg.sender,"Not owner");
        require(duration < 14 days,"Auction can't last more than 14 days");
        require(price != 0,"Can't start at 0");
        NFT.transferFrom(msg.sender,address(this),tokenId);
        listed[tokenId] = 2;
        auctionSales[tokenId] = auctionListing(msg.sender,duration,0,price,address(0));
        emit tokenListed(msg.sender, tokenId,2,price);
    }

    function buyToken(uint tokenId,uint amount) external {
        require(listed[tokenId] == 1,"Token not direct listed");
        directListing storage listing = directSales[tokenId];
        require(listing.owner != msg.sender,"Can't buy own token");
        require(amount >= listing.price,"Not enough paid");
        require(PaymentToken.transferFrom(msg.sender,address(this), amount),"Payment not received");
        uint fee = amount * FEE/10_000;
        balance[listing.owner] += amount - fee;
        FEEBalance += fee;
        NFT.transferFrom(address(this),msg.sender,tokenId);
        delete directSales[tokenId];
        delete listed[tokenId];
        emit tokenBought(msg.sender,tokenId);
    }

    function bidToken(uint tokenId,uint amount) external {
        require(listed[tokenId] == 2,"Token not auction listed");
        auctionListing storage listing = auctionSales[tokenId];
        require(listing.owner != msg.sender,"Can't buy own token");
        require(amount > listing.highestBid + differentialAmount,"Bid higher");
        require(PaymentToken.transferFrom(msg.sender, address(this), amount),"Payment not made");
        require(msg.sender != listing.highestBidder,"Can't bid twice");
        require(block.timestamp < listing.timeEnd || listing.timeEnd == 0,"Auction over");
        if(listing.highestBidder != address(0)){
            balance[listing.highestBidder] += listing.highestBid;
        }
        else{
            listing.timeEnd = block.timestamp + listing.duration;
        }
        listing.highestBid = amount;
        listing.highestBidder = msg.sender;
        emit receivedBid(msg.sender,tokenId,amount);
    }

    function retrieveToken(uint tokenId) external{
        require(listed[tokenId] == 2,"Token not auction listed");
        auctionListing storage listing = auctionSales[tokenId];
        require(block.timestamp >= listing.timeEnd,"Auction not over");
        require(listing.highestBidder != address(0),"Token not sold");
        require(msg.sender == listing.highestBidder,"Not highest bidder");  
        uint fee = listing.highestBid * FEE/10_000;
        balance[listing.owner] += listing.highestBid - fee;
        FEEBalance += fee;
        NFT.transferFrom(address(this),msg.sender,tokenId);
        emit tokenBought(msg.sender,tokenId);
        delete auctionSales[tokenId];
        delete listed[tokenId];
    }

    function delistToken(uint[] memory tokenId) external{
        uint length = tokenId.length;
        for(uint i=0;i<length;i++){
            require(listed[tokenId[i]] != 0,"Token not listed");
            if(listed[tokenId[i]] == 1){
                require(directSales[tokenId[i]].owner == msg.sender,"Not owner");
                NFT.transferFrom(address(this),msg.sender,tokenId[i]);
                delete directSales[tokenId[i]];
                delete listed[tokenId[i]];
                emit tokenDeListed(tokenId[i], 1);
            }
            else{
                require(auctionSales[tokenId[i]].owner == msg.sender,"Not owner");
                require(auctionSales[tokenId[i]].timeEnd > block.timestamp || auctionSales[tokenId[i]].highestBidder == address(0),"Auction over or received bids");
                NFT.transferFrom(address(this),msg.sender,tokenId[i]);
                delete auctionSales[tokenId[i]];
                delete listed[tokenId[i]];
                emit tokenDeListed(tokenId[i],2);
            }
        }
    }

    function retrieveBalance() external {
        uint amount = balance[msg.sender];
        balance[msg.sender] = 0;
        PaymentToken.transfer(msg.sender,amount);
    }

    function retrieveFee() external onlyOwner{
        uint amount = FEEBalance;
        FEEBalance = 0;
        PaymentToken.transfer(msg.sender,amount);
    }

    function setFee(uint _fee) external onlyOwner{
        FEE = _fee;
    }

    function setPriceDifferential(uint _amount) external onlyOwner{
        differentialAmount = _amount;
    }

}