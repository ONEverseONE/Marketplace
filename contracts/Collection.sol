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
    uint public royaltyBalance;
    uint public FEEBalance;
    uint public differentialAmount = 10 ether;

    address public creatorAddress;

    mapping(address=>bool) public isApproved;

    // mapping(address=>uint) public balance;
    mapping(uint=>uint) public listed; //0 - not, 1 = direct, 2 = auction

    mapping(uint=>directListing) public directSales;
    mapping(uint=>auctionListing) public auctionSales;

    event tokenListed(address indexed owner,uint indexed tokenId,uint8 listingType,uint price);
    event tokenBought(address indexed buyer,uint indexed tokenId);
    event receivedBid(address indexed bidder,uint indexed tokenId,uint amount);
    event tokenDeListed(uint indexed tokenId,uint8 listingType);

    constructor(address _collection,address _token,address _creator,uint _percentage) {
        NFT = IERC721(_collection);
        PaymentToken = IERC20(_token);
        creatorAddress = _creator;
        royaltyPercentage = _percentage;
    }

    modifier onlyCreator{
        require(msg.sender == creatorAddress,"Not creator");
        _;
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
        uint royalty = amount * royaltyPercentage / 10_000;
        PaymentToken.transfer(listing.owner,amount-fee-royalty);
        // balance[listing.owner] += amount - fee - royalty;
        FEEBalance += fee;
        royaltyBalance += royalty;
        NFT.transferFrom(address(this),msg.sender,tokenId);
        delete directSales[tokenId];
        delete listed[tokenId];
        emit tokenBought(msg.sender,tokenId);
    }

    function bidToken(uint tokenId,uint amount) external {
        require(listed[tokenId] == 2,"Token not auction listed");
        auctionListing storage listing = auctionSales[tokenId];
        require(listing.owner != msg.sender,"Can't buy own token");
        require(msg.sender != listing.highestBidder,"Can't bid twice");
        require(block.timestamp < listing.timeEnd || listing.timeEnd == 0,"Auction over");
        if(listing.highestBidder != address(0)){
            require(amount >= listing.highestBid + differentialAmount,"Bid higher");
            PaymentToken.transfer(listing.highestBidder,listing.highestBid);
        }
        else{
            require(amount >= listing.highestBid,"Bid higher");
            listing.timeEnd = block.timestamp + listing.duration;
        }
        require(PaymentToken.transferFrom(msg.sender, address(this), amount),"Payment not made");
        listing.highestBid = amount;
        listing.highestBidder = msg.sender;
        emit receivedBid(msg.sender,tokenId,amount);
    }

    function retrieveToken(uint tokenId) external{
        require(listed[tokenId] == 2,"Token not auction listed");
        auctionListing storage listing = auctionSales[tokenId];
        require(block.timestamp >= listing.timeEnd,"Auction not over");
        require(listing.highestBidder != address(0),"Token not sold");
        require(msg.sender == listing.highestBidder || msg.sender == listing.owner,"Not highest bidder or owner");  
        uint fee = listing.highestBid * FEE/10_000;
        uint royalty = listing.highestBid * royaltyPercentage/10_000;
        // balance[listing.owner] += listing.highestBid - fee - royalty;
        PaymentToken.transfer(listing.owner,listing.highestBid-fee-royalty);
        FEEBalance += fee;
        royaltyBalance += royalty;
        NFT.transferFrom(address(this),listing.highestBidder,tokenId);
        emit tokenBought(listing.highestBidder,tokenId);
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
                if(auctionSales[tokenId[i]].highestBidder != address(0)){
                    PaymentToken.transfer(auctionSales[tokenId[i]].highestBidder,auctionSales[tokenId[i]].highestBid);
                    // balance[auctionSales[tokenId[i]].highestBidder] += auctionSales[tokenId[i]].highestBid;
                }
                delete auctionSales[tokenId[i]];
                delete listed[tokenId[i]];
                emit tokenDeListed(tokenId[i],2);
            }
        }
    }

    // function retrieveBalance() external {
    //     uint amount = balance[msg.sender];
    //     balance[msg.sender] = 0;
    //     PaymentToken.transfer(msg.sender,amount);
    // }

    function retrieveFee(address _to) external {
        require(msg.sender == owner() || isApproved[msg.sender],"Not owner or approved");
        uint amount = FEEBalance;
        FEEBalance = 0;
        PaymentToken.transfer(_to,amount);
    }

    function setRoyaltyPercentage(uint _percentage) external onlyOwner{
        royaltyPercentage = _percentage;
    }

    function setCreatorAddress(address _creator) external onlyOwner{
        creatorAddress = _creator;
    }

    function setApproved(address _address,bool _approve) external onlyOwner{
        isApproved[_address] = _approve;
    }

    function retrieveRoyalty(address _to) external onlyCreator{
        uint amount = royaltyBalance;
        royaltyBalance = 0;
        PaymentToken.transfer(_to,amount);
    }

    function setNFT(address _nft) external onlyOwner{
        NFT = IERC721(_nft);
    }

    function setPaymentToken(address _token) external onlyOwner{
        PaymentToken = IERC20(_token);
    }

    function setFee(uint _fee) external onlyOwner{
        FEE = _fee;
    }

    function setPriceDifferential(uint _amount) external onlyOwner{
        differentialAmount = _amount;
    }

}