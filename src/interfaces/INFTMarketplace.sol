// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface INFTMarketplace {
    event ListingCreated(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 amount, uint256 price, bool isERC721);
    event ListingCancelled(uint256 indexed listingId);
    event SaleCompleted(uint256 indexed listingId, address indexed buyer, address indexed seller, uint256 price);
    event NFTMinted(address indexed creator, address indexed nftContract, uint256 tokenId, bool isERC721);
    event NFTStaked(uint256 indexed listingId, address indexed staker, uint256 duration);
    event NFTBorrowed(uint256 indexed listingId, address indexed borrower, uint256 duration);

    function createListing(address nftContract, uint256 tokenId, uint256 amount, uint256 price, bool isERC721) external;
    function purchaseNFT(uint256 listingId) external payable;
    function cancelListing(uint256 listingId) external;
    function mintNFT(address to, string calldata uri, bool isERC721) external;
    function stakeNFT(uint256 listingId, uint256 duration) external;
    function borrowNFT(uint256 listingId, uint256 duration) external;
}