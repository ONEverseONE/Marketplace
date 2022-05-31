//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract testNFT is ERC721Enumerable{

    uint tokenId;

    constructor() ERC721("test Land","Land"){}

    function mint(uint amount) external{
        for(uint i=0;i<amount;i++){
            tokenId++;
            _safeMint(msg.sender,tokenId);
        }
    }
}