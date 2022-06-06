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

    // IERC721 NFT;
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

    struct collectionInfo{
        address creator;
        uint royaltyPercentage;
        uint royaltyBalance;
    }

    // struct delistTokens{
    //     address _contract;
    //     uint[] tokenIds;
    // }

    uint public FEE = 200; //2% since we divide by 10_000
    uint public FEEBalance;
    uint public differentialAmount = 10 ether;

    mapping(address=>bool) public isApproved;
    mapping(address=>bool) public whitelistContracts;
    mapping(address=>collectionInfo) public royaltyInfo;

    mapping(address=>mapping(uint=>uint)) public listed; //0 - not, 1 = direct, 2 = auction

    mapping(address=>mapping(uint=>directListing)) public directSales;
    mapping(address=>mapping(uint=>auctionListing)) public auctionSales;

    event tokenListed(address indexed _contract,address indexed owner,uint indexed tokenId,uint8 listingType,uint price,uint duration);
    event tokenBought(address indexed _contract,address indexed buyer,uint indexed tokenId);
    event receivedBid(address indexed _contract,address indexed bidder,uint indexed tokenId,uint amount);
    event tokenDeListed(address indexed _contract,uint indexed tokenId,uint8 listingType);
    event marketplaceStarted(address indexed _contract,address indexed creator,uint royaltyPercentage);

    constructor(address _paymentToken) {
        PaymentToken = IERC20(_paymentToken);
    }

    //@notice direct listing
    function listToken(address _contract,uint tokenId,uint price) external {
        require(whitelistContracts[_contract],"Contract not listed");
        IERC721 NFT = IERC721(_contract);
        require(NFT.ownerOf(tokenId) == msg.sender,"Not owner");
        require(price != 0,"Can't sell for free");
        NFT.transferFrom(msg.sender, address(this), tokenId);
        listed[_contract][tokenId] = 1;
        directSales[_contract][tokenId] = directListing(msg.sender,price);
        emit tokenListed(_contract,msg.sender, tokenId,1,price,0);
    }

    //@notice auction listing
    function listToken(address _contract,uint tokenId,uint price,uint duration) external {
        require(whitelistContracts[_contract],"Contract not listed");
        IERC721 NFT = IERC721(_contract);
        require(NFT.ownerOf(tokenId) == msg.sender,"Not owner");
        require(duration < 14 days,"Auction can't last more than 14 days");
        require(price != 0,"Can't start at 0");
        NFT.transferFrom(msg.sender,address(this),tokenId);
        listed[_contract][tokenId] = 2;
        auctionSales[_contract][tokenId] = auctionListing(msg.sender,duration,0,price,address(0));
        emit tokenListed(_contract,msg.sender, tokenId,2,price,duration);
    }

    function buyToken(address _contract,uint tokenId,uint amount) external {
        IERC721 NFT = IERC721(_contract);
        require(listed[_contract][tokenId] == 1,"Token not direct listed");
        directListing storage listing = directSales[_contract][tokenId];
        require(listing.owner != msg.sender,"Can't buy own token");
        require(amount >= listing.price,"Not enough paid");
        require(PaymentToken.transferFrom(msg.sender,address(this), amount),"Payment not received");
        uint fee = amount * FEE/10_000;
        uint royalty = amount * royaltyInfo[_contract].royaltyPercentage / 10_000;
        PaymentToken.transfer(listing.owner,amount-fee-royalty);
        FEEBalance += fee;
        royaltyInfo[_contract].royaltyBalance += royalty;
        NFT.transferFrom(address(this),msg.sender,tokenId);
        delete directSales[_contract][tokenId];
        delete listed[_contract][tokenId];
        emit tokenBought(_contract,msg.sender,tokenId);
    }

    function bidToken(address _contract,uint tokenId,uint amount) external {
        require(listed[_contract][tokenId] == 2,"Token not auction listed");
        auctionListing storage listing = auctionSales[_contract][tokenId];
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
        emit receivedBid(_contract,msg.sender,tokenId,amount);
    }

    function retrieveToken(address _contract,uint tokenId) external{
        IERC721 NFT = IERC721(_contract);
        require(listed[_contract][tokenId] == 2,"Token not auction listed");
        auctionListing storage listing = auctionSales[_contract][tokenId];
        require(block.timestamp >= listing.timeEnd,"Auction not over");
        require(listing.highestBidder != address(0),"Token not sold");
        require(msg.sender == listing.highestBidder || msg.sender == listing.owner,"Not highest bidder or owner");  
        uint fee = listing.highestBid * FEE/10_000;
        uint royalty = listing.highestBid * royaltyInfo[_contract].royaltyPercentage/10_000;
        PaymentToken.transfer(listing.owner,listing.highestBid-fee-royalty);
        FEEBalance += fee;
        royaltyInfo[_contract].royaltyBalance += royalty;
        NFT.transferFrom(address(this),listing.highestBidder,tokenId);
        emit tokenBought(_contract,listing.highestBidder,tokenId);
        delete auctionSales[_contract][tokenId];
        delete listed[_contract][tokenId];
    }

    function delistToken(address[] calldata _contract,uint[] calldata tokenId) external{
        uint length = tokenId.length;
        for(uint i=0;i<length;i++){
            require(listed[_contract[i]][tokenId[i]] != 0,"Token not listed");
            IERC721 NFT = IERC721(_contract[i]);
            if(listed[_contract[i]][tokenId[i]] == 1){
                require(directSales[_contract[i]][tokenId[i]].owner == msg.sender,"Not owner");
                NFT.transferFrom(address(this),msg.sender,tokenId[i]);
                delete directSales[_contract[i]][tokenId[i]];
                delete listed[_contract[i]][tokenId[i]];
                emit tokenDeListed(_contract[i],tokenId[i], 1);
            }
            else{
                require(auctionSales[_contract[i]][tokenId[i]].owner == msg.sender,"Not owner");
                require(auctionSales[_contract[i]][tokenId[i]].timeEnd > block.timestamp || auctionSales[_contract[i]][tokenId[i]].highestBidder == address(0),"Auction over or received bids");
                NFT.transferFrom(address(this),msg.sender,tokenId[i]);
                if(auctionSales[_contract[i]][tokenId[i]].highestBidder != address(0)){
                    PaymentToken.transfer(auctionSales[_contract[i]][tokenId[i]].highestBidder,auctionSales[_contract[i]][tokenId[i]].highestBid);
                }
                delete auctionSales[_contract[i]][tokenId[i]];
                delete listed[_contract[i]][tokenId[i]];
                emit tokenDeListed(_contract[i],tokenId[i],2);
            }
        }
    }

    function whitelistContract(address _contract,bool _whitelist) external onlyOwner{
        whitelistContracts[_contract] = _whitelist;
    }

    function retrieveFee(address _to) external {
        require(msg.sender == owner() || isApproved[msg.sender],"Not owner or approved");
        uint amount = FEEBalance;
        FEEBalance = 0;
        PaymentToken.transfer(_to,amount);
    }

    function setMarketplace(address _contract,address _creator,uint royaltyPercentage) external onlyOwner{
        royaltyInfo[_contract] = collectionInfo(_creator,royaltyPercentage,0);
        whitelistContracts[_contract] = true;
        emit marketplaceStarted(_contract, _creator, royaltyPercentage);
    }

    function editMarketplace(address _contract,address _creator,uint royaltyPercentage) external onlyOwner{
        royaltyInfo[_contract].creator = _creator;
        royaltyInfo[_contract].royaltyPercentage = royaltyPercentage;
    }

    function setApproved(address _address,bool _approve) external onlyOwner{
        isApproved[_address] = _approve;
    }

    function retrieveRoyalty(address _contract,address _to) external {
        require(royaltyInfo[_contract].creator == msg.sender,"Not creator");
        uint amount = royaltyInfo[_contract].royaltyBalance;
        royaltyInfo[_contract].royaltyBalance = 0;
        PaymentToken.transfer(_to,amount);
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