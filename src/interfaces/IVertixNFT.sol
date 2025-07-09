// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Interface for the VertixNFT contract
interface IVertixNFT is IERC721 {
    // Struct for collection details
    struct Collection {
        address creator;
        string name;
        string symbol;
        string image;
        uint8 maxSupply;
        uint8 currentSupply;
        uint256[] tokenIds;
    }

    // Create a new collection
    function createCollection(string calldata name, string calldata symbol, string calldata image, uint8 maxSupply)
        external
        returns (uint256);

    // Mint an NFT to a collection
    function mintToCollection(address to, uint256 collectionId, string calldata uri, bytes32 metadataHash, uint96 royaltyBps) external;

    // Mint a single NFT (no collection)
    function mintSingleNft(address to, string calldata uri, bytes32 metadataHash, uint96 royaltyBps) external;

    // Mint an NFT for a social media account
    function mintSocialMediaNft(
        address to,
        string calldata socialMediaId,
        string calldata uri,
        bytes32 metadataHash,
        uint96 royaltyBps,
        bytes calldata signature
    ) external;

    // Commented out functions - not currently implemented
    // function getCollectionTokens(uint256 collectionId) external view returns (uint256[] memory);
    // function getCollectionDetails(uint256 collectionId) external view returns (...);

    function getUsedSocialMediaIds(string calldata socialMediaId) external view returns (bool);

    // Events
    event CollectionCreated(
        uint256 indexed collectionId,
        address indexed creator,
        string name,
        string symbol,
        string image,
        uint256 maxSupply
    );
    event NFTMinted(
        address indexed to, uint256 indexed tokenId, uint256 collectionId, string uri, bytes32 metadataHash
    );
    event SocialMediaNFTMinted(
        address indexed to, uint256 indexed tokenId, string socialMediaId, string uri, bytes32 metadataHash
    );
}
