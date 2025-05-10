// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Interface for the VertixNFT contract
interface IVertixNFT {
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
    function mintToCollection(address to, uint256 collectionId, string calldata uri, bytes32 metadataHash) external;

    // Mint a single NFT (no collection)
    function mintSingleNFT(address to, string calldata uri, bytes32 metadataHash) external;

    // Mint an NFT for a social media account
    function mintSocialMediaNFT(
        address to,
        string calldata socialMediaId,
        string calldata uri,
        bytes32 metadataHash,
        bytes calldata signature
    ) external;

    // Get collection tokens
    function getCollectionTokens(uint256 collectionId) external view returns (uint256[] memory);

    // Get collection details
    function getCollectionDetails(uint256 collectionId)
        external
        view
        returns (
            address creator,
            string memory name,
            string memory symbol,
            string memory image,
            uint256 maxSupply,
            uint256 currentSupply
        );

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
