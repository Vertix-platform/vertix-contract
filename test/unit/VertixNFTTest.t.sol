// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {VertixNFT} from "../../src/VertixNFT.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {DeployVertix} from "../../script/DeployVertix.s.sol";

contract VertixNFTV2Mock is VertixNFT {
    uint256 private newFeature;

    function setNewFeature(uint256 _value) external onlyOwner {
        newFeature = _value;
    }

    function getNewFeature() external view returns (uint256) {
        return newFeature;
    }
}

contract VertixNFTTest is Test {
    // DeployVertix script instance
    DeployVertix public deployer;

    // Contract addresses from deployment
    DeployVertix.VertixAddresses public vertixAddresses;

    // Contract instances
    VertixNFT public nft;

    address public owner;
    address public creator = makeAddr("creator");
    address public user = makeAddr("user");
    address public verificationServer;
    uint256 public verificationServerPk; // Private key for verificationServer
    address public recipient = makeAddr("recipient");

    uint256 public constant COLLECTION_ID = 1;
    uint256 public constant TOKEN_ID = 1;
    uint8 public constant MAX_SUPPLY = 10;
    uint96 public constant ROYALTY_BPS = 500; // 5%
    string public constant NAME = "Test Collection";
    string public constant SYMBOL = "TST";
    string public constant IMAGE = "ipfs://collection-image";
    string public constant TOKEN_URI = "ipfs://token-uri";
    string public constant SOCIAL_MEDIA_ID = "user123";
    string public constant SOCIAL_MEDIA_ID_2 = "user124"; // Added for used ID test
    bytes32 public constant METADATA_HASH = bytes32(uint256(123456789));

    event CollectionCreated(
        uint256 indexed collectionId,
        address indexed creator,
        string name,
        string symbol,
        string image,
        uint256 maxSupply
    );
    event NFTMinted(
        address indexed to,
        uint256 indexed tokenId,
        uint256 collectionId,
        string uri,
        bytes32 metadataHash,
        address royaltyRecipient,
        uint96 royaltyBps
    );
    event SocialMediaNFTMinted(
        address indexed to,
        uint256 indexed tokenId,
        string socialMediaId,
        string uri,
        bytes32 metadataHash,
        address indexed royaltyRecipient,
        uint96 royaltyBps
    );

    function setUp() public {
        // Use the same verification server address as the deployed contract
        verificationServer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        verificationServerPk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        // Create deployer instance
        deployer = new DeployVertix();

        // Deploy all contracts using the DeployVertix script
        vertixAddresses = deployer.deployVertix();

        // Get the NFT contract instance
        nft = VertixNFT(vertixAddresses.nft);

        // Get the owner from the NFT contract
        owner = nft.owner();

        // Fund test accounts
        vm.deal(creator, 1 ether);
        vm.deal(user, 1 ether);
        vm.deal(recipient, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Helper function to get the NFT implementation address for upgrade testing
     */
    function getNFTImplementation() internal returns (address) {
        return address(new VertixNFT());
    }

    /*//////////////////////////////////////////////////////////////
                    DEPLOYMENT VERIFICATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeploymentVerification() public view {
        // Verify that the NFT contract was deployed correctly
        assertTrue(vertixAddresses.nft != address(0), "NFT should be deployed");
        assertTrue(vertixAddresses.governance != address(0), "Governance should be deployed");
        assertTrue(vertixAddresses.escrow != address(0), "Escrow should be deployed");

        // Verify that NFT has correct owner
        assertEq(nft.owner(), owner, "NFT should have correct owner");

        // Verify initial state
        assertEq(nft.name(), "VertixNFT", "NFT should have correct name");
        assertEq(nft.symbol(), "VNFT", "NFT should have correct symbol");
    }

    /*//////////////////////////////////////////////////////////////
                    INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialization() public view {
        assertEq(nft.owner(), owner);
        assertEq(nft.name(), "VertixNFT");
        assertEq(nft.symbol(), "VNFT");
    }

    function test_CannotReinitialize() public {
        vm.prank(owner);
        vm.expectRevert();
        nft.initialize(verificationServer);
    }

    function test_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        nft.transferOwnership(newOwner);
        assertEq(nft.owner(), newOwner);
    }

    function test_RenounceOwnership() public {
        vm.prank(owner);
        nft.renounceOwnership();
        assertEq(nft.owner(), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    COLLECTION CREATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateCollection() public {
        vm.prank(creator);
        vm.expectEmit(true, true, false, true);
        emit CollectionCreated(COLLECTION_ID, creator, NAME, SYMBOL, IMAGE, MAX_SUPPLY);

        uint256 collectionId = nft.createCollection(NAME, SYMBOL, IMAGE, MAX_SUPPLY);

        // (
        //     address collectionCreator,
        //     string memory name,
        //     string memory symbol,
        //     string memory image,
        //     uint256 maxSupply,
        //     uint256 currentSupply
        // ) = nft.getCollectionDetails(collectionId);

        assertEq(collectionId, COLLECTION_ID);
        // assertEq(collectionCreator, creator);
        // assertEq(name, NAME);
        // assertEq(symbol, SYMBOL);
        // assertEq(image, IMAGE);
        // assertEq(maxSupply, MAX_SUPPLY);
        // assertEq(currentSupply, 0);
    }

    function test_RevertIf_CreateCollectionWithEmptyName() public {
        vm.prank(creator);
        vm.expectRevert(VertixNFT.VertixNFT__EmptyString.selector);
        nft.createCollection("", SYMBOL, IMAGE, MAX_SUPPLY);
    }

    function test_RevertIf_CreateCollectionWithEmptySymbol() public {
        vm.prank(creator);
        vm.expectRevert(VertixNFT.VertixNFT__EmptyString.selector);
        nft.createCollection(NAME, "", IMAGE, MAX_SUPPLY);
    }

    function test_RevertIf_CreateCollectionWithZeroSupply() public {
        vm.prank(creator);
        vm.expectRevert(VertixNFT.VertixNFT__ZeroSupply.selector);
        nft.createCollection(NAME, SYMBOL, IMAGE, 0);
    }

    function test_RevertIf_CreateCollectionExceedsMaxSize() public {
        vm.prank(creator);
        vm.expectRevert(VertixNFT.VertixNFT__ExceedsMaxCollectionSize.selector);
        nft.createCollection(NAME, SYMBOL, IMAGE, 1001); // MAX_COLLECTION_SIZE is 100
    }

    /*//////////////////////////////////////////////////////////////
                    MINT TO COLLECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintToCollection() public {
        vm.prank(creator);
        uint256 collectionId = nft.createCollection(NAME, SYMBOL, IMAGE, MAX_SUPPLY);

        console.log("collectionId", collectionId);

        // Verify initial supply is 0
        (,,,,, uint256 initialSupply) = nft.getCollectionDetails(collectionId);
        assertEq(initialSupply, 0);

        vm.prank(creator);
        nft.mintToCollection(recipient, collectionId, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);

        // Verify currentSupply was incremented
        (,,,,, uint256 currentSupply) = nft.getCollectionDetails(collectionId);
        assertEq(currentSupply, 1);

        // Use the expected token ID (1 for first NFT)
        uint256 tokenId = 1;
        assertEq(nft.tokenToCollection(tokenId), collectionId);
        assertEq(nft.ownerOf(tokenId), recipient);
        assertEq(nft.tokenURI(tokenId), TOKEN_URI);
        assertEq(nft.metadataHashes(tokenId), METADATA_HASH);
        (address royaltyRecipient, uint256 royaltyAmount) = nft.royaltyInfo(tokenId, 1 ether);
        assertEq(royaltyRecipient, creator);
        assertEq(royaltyAmount, (1 ether * ROYALTY_BPS) / 10000);
    }

    function test_RevertIf_MintToNonExistentCollection() public {
        vm.prank(creator);
        vm.expectRevert(VertixNFT.VertixNFT__InvalidCollection.selector);
        nft.mintToCollection(recipient, COLLECTION_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
    }

    function test_RevertIf_MintToInvalidCollection() public {
        vm.prank(creator);
        vm.expectRevert(VertixNFT.VertixNFT__InvalidCollection.selector);
        nft.mintToCollection(recipient, 0, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
    }

    function test_RevertIf_NonCreatorMintsToCollection() public {
        vm.prank(creator);
        nft.createCollection(NAME, SYMBOL, IMAGE, MAX_SUPPLY);

        vm.prank(user);
        vm.expectRevert(VertixNFT.VertixNFT__NotCollectionCreator.selector);
        nft.mintToCollection(recipient, COLLECTION_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
    }

    function test_RevertIf_MintToCollectionExceedsMaxSupply() public {
        vm.prank(creator);
        nft.createCollection(NAME, SYMBOL, IMAGE, 1);

        vm.prank(creator);
        nft.mintToCollection(recipient, COLLECTION_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);

        vm.prank(creator);
        vm.expectRevert(VertixNFT.VertixNFT__MaxSupplyReached.selector);
        nft.mintToCollection(recipient, COLLECTION_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
    }

    function test_RevertIf_MintToCollectionWithExcessiveRoyalty() public {
        uint96 excessiveRoyalty = uint96(nft.MAX_ROYALTY_BPS()) + 1;
        vm.prank(creator);
        nft.createCollection(NAME, SYMBOL, IMAGE, MAX_SUPPLY);

        vm.prank(creator);
        vm.expectRevert(VertixNFT.VertixNFT__InvalidRoyaltyPercentage.selector);
        nft.mintToCollection(recipient, COLLECTION_ID, TOKEN_URI, METADATA_HASH, excessiveRoyalty);
    }

    /*//////////////////////////////////////////////////////////////
                    SINGLE NFT MINTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintSingleNFT() public {
        vm.prank(creator);

        // Mint the NFT
        nft.mintSingleNft(recipient, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);

        // Verify the NFT was minted correctly
        uint256 tokenId = 1;
        assertEq(nft.ownerOf(tokenId), recipient);
        assertEq(nft.tokenURI(tokenId), TOKEN_URI);
        assertEq(nft.metadataHashes(tokenId), METADATA_HASH);
        assertEq(nft.tokenToCollection(tokenId), 0);
        (address royaltyRecipient, uint256 royaltyAmount) = nft.royaltyInfo(tokenId, 1 ether);
        assertEq(royaltyRecipient, creator);
        assertEq(royaltyAmount, (1 ether * ROYALTY_BPS) / 10000);
    }

    function test_RevertIf_MintSingleNFTWithExcessiveRoyalty() public {
        uint96 excessiveRoyalty = uint96(nft.MAX_ROYALTY_BPS()) + 1;
        vm.prank(creator);
        vm.expectRevert(VertixNFT.VertixNFT__InvalidRoyaltyPercentage.selector);
        nft.mintSingleNft(recipient, TOKEN_URI, METADATA_HASH, excessiveRoyalty);
    }

    /*//////////////////////////////////////////////////////////////
                    SOCIAL MEDIA NFT MINTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintSocialMediaNFT() public {
        bytes32 messageHash = keccak256(abi.encodePacked(recipient, SOCIAL_MEDIA_ID));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verificationServerPk, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit SocialMediaNFTMinted(
            recipient, TOKEN_ID, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, recipient, ROYALTY_BPS
        );

        nft.mintSocialMediaNft(recipient, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS, signature);

        assertEq(nft.ownerOf(TOKEN_ID), recipient);
        assertEq(nft.tokenURI(TOKEN_ID), TOKEN_URI);
        assertEq(nft.metadataHashes(TOKEN_ID), METADATA_HASH);
        assertTrue(nft.usedSocialMediaIds(SOCIAL_MEDIA_ID));
        (address royaltyRecipient, uint256 royaltyAmount) = nft.royaltyInfo(TOKEN_ID, 1 ether);
        assertEq(royaltyRecipient, recipient);
        assertEq(royaltyAmount, (1 ether * ROYALTY_BPS) / 10000);
    }

    function test_RevertIf_MintSocialMediaNFTWithUsedId() public {
        // First mint
        bytes32 messageHash = keccak256(abi.encodePacked(recipient, SOCIAL_MEDIA_ID));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verificationServerPk, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(user);
        nft.mintSocialMediaNft(recipient, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS, signature);

        // Second mint with same social media ID
        vm.prank(user);
        vm.expectRevert(VertixNFT.VertixNFT__SocialMediaIdAlreadyUsed.selector);
        nft.mintSocialMediaNft(recipient, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS, signature);
    }

    function test_RevertIf_MintSocialMediaNFTWithInvalidSignature() public {
        bytes32 messageHash = keccak256(abi.encodePacked(recipient, SOCIAL_MEDIA_ID));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(makeAddr("invalidSigner"))), ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(user);
        vm.expectRevert(VertixNFT.VertixNFT__InvalidSignature.selector);
        nft.mintSocialMediaNft(recipient, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS, signature);
    }

    function test_RevertIf_MintSocialMediaNFTWithExcessiveRoyalty() public {
        bytes32 messageHash = keccak256(abi.encodePacked(recipient, SOCIAL_MEDIA_ID));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(verificationServer)), ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        uint96 excessiveRoyalty = uint96(nft.MAX_ROYALTY_BPS()) + 1;

        vm.prank(user);
        vm.expectRevert(VertixNFT.VertixNFT__InvalidRoyaltyPercentage.selector);
        nft.mintSocialMediaNft(recipient, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, excessiveRoyalty, signature);
    }

    /*//////////////////////////////////////////////////////////////
                    GLOBAL TOKEN ID COUNTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GlobalTokenIdCounter_AllNFTTypes() public {
        // Test that all NFT types use the same global token ID counter
        
        // 1. Mint a single NFT - should get token ID 1
        vm.prank(creator);
        nft.mintSingleNft(recipient, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
        assertEq(nft.ownerOf(1), recipient);
        assertEq(nft.tokenToCollection(1), 0); // Single NFT has no collection

        // 2. Create a collection
        vm.prank(creator);
        uint256 collectionId = nft.createCollection(NAME, SYMBOL, IMAGE, MAX_SUPPLY);

        // 3. Mint to collection - should get token ID 2
        vm.prank(creator);
        nft.mintToCollection(recipient, collectionId, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
        assertEq(nft.ownerOf(2), recipient);
        assertEq(nft.tokenToCollection(2), collectionId);
        
        // Verify currentSupply was incremented
        (,,,,, uint256 currentSupply) = nft.getCollectionDetails(collectionId);
        assertEq(currentSupply, 1);

        // 4. Mint another single NFT - should get token ID 3
        vm.prank(creator);
        nft.mintSingleNft(user, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
        assertEq(nft.ownerOf(3), user);
        assertEq(nft.tokenToCollection(3), 0);

        // 5. Mint a social media NFT - should get token ID 4
        bytes32 messageHash = keccak256(abi.encodePacked(user, SOCIAL_MEDIA_ID_2));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verificationServerPk, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(user);
        nft.mintSocialMediaNft(user, SOCIAL_MEDIA_ID_2, TOKEN_URI, METADATA_HASH, ROYALTY_BPS, signature);
        assertEq(nft.ownerOf(4), user);
        assertEq(nft.tokenToCollection(4), 0); // Social media NFT has no collection

        // 6. Mint another NFT to the same collection - should get token ID 5
        vm.prank(creator);
        nft.mintToCollection(user, collectionId, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
        assertEq(nft.ownerOf(5), user);
        assertEq(nft.tokenToCollection(5), collectionId);
        
        // Verify currentSupply was incremented again
        (,,,,, uint256 finalSupply) = nft.getCollectionDetails(collectionId);
        assertEq(finalSupply, 2);

        // Verify all NFTs exist and have correct properties
        assertEq(nft.ownerOf(1), recipient);
        assertEq(nft.ownerOf(2), recipient);
        assertEq(nft.ownerOf(3), user);
        assertEq(nft.ownerOf(4), user);
        assertEq(nft.ownerOf(5), user);

        // Verify collection mapping
        assertEq(nft.tokenToCollection(1), 0); // Single NFT
        assertEq(nft.tokenToCollection(2), collectionId); // Collection NFT
        assertEq(nft.tokenToCollection(3), 0); // Single NFT
        assertEq(nft.tokenToCollection(4), 0); // Social media NFT
        assertEq(nft.tokenToCollection(5), collectionId); // Collection NFT

        // Verify social media ID tracking
        assertTrue(nft.usedSocialMediaIds(SOCIAL_MEDIA_ID_2));
        assertFalse(nft.usedSocialMediaIds("unused_id"));

        // Verify metadata hashes
        assertEq(nft.metadataHashes(1), METADATA_HASH);
        assertEq(nft.metadataHashes(2), METADATA_HASH);
        assertEq(nft.metadataHashes(3), METADATA_HASH);
        assertEq(nft.metadataHashes(4), METADATA_HASH);
        assertEq(nft.metadataHashes(5), METADATA_HASH);

        // Verify token URIs
        assertEq(nft.tokenURI(1), TOKEN_URI);
        assertEq(nft.tokenURI(2), TOKEN_URI);
        assertEq(nft.tokenURI(3), TOKEN_URI);
        assertEq(nft.tokenURI(4), TOKEN_URI);
        assertEq(nft.tokenURI(5), TOKEN_URI);
    }

    function test_GlobalTokenIdCounter_SequentialMinting() public {
        // Test sequential minting to ensure token IDs are consecutive
        
        address[] memory recipients = new address[](5);
        recipients[0] = makeAddr("recipient1");
        recipients[1] = makeAddr("recipient2");
        recipients[2] = makeAddr("recipient3");
        recipients[3] = makeAddr("recipient4");
        recipients[4] = makeAddr("recipient5");

        // Fund recipients
        for (uint256 i = 0; i < 5; i++) {
            vm.deal(recipients[i], 1 ether);
        }

        // Mint 5 single NFTs sequentially
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(creator);
            nft.mintSingleNft(recipients[i], TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
            
            // Verify token ID is sequential (starting from 1)
            assertEq(nft.ownerOf(i + 1), recipients[i]);
            assertEq(nft.tokenToCollection(i + 1), 0);
        }

        // Verify all token IDs are consecutive
        for (uint256 i = 1; i <= 5; i++) {
            assertEq(nft.ownerOf(i), recipients[i - 1]);
        }
    }

    function test_GlobalTokenIdCounter_MixedMinting() public {
        // Test mixed minting order to ensure global counter works correctly
        
        // 1. Mint single NFT (token ID 1)
        vm.prank(creator);
        nft.mintSingleNft(recipient, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
        assertEq(nft.ownerOf(1), recipient);

        // 2. Create collection
        vm.prank(creator);
        uint256 collectionId = nft.createCollection(NAME, SYMBOL, IMAGE, MAX_SUPPLY);

        // 3. Mint to collection (token ID 2)
        vm.prank(creator);
        nft.mintToCollection(recipient, collectionId, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
        assertEq(nft.ownerOf(2), recipient);

        // 4. Mint social media NFT (token ID 3)
        bytes32 messageHash = keccak256(abi.encodePacked(user, SOCIAL_MEDIA_ID));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verificationServerPk, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(user);
        nft.mintSocialMediaNft(user, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS, signature);
        assertEq(nft.ownerOf(3), user);

        // 5. Mint another single NFT (token ID 4)
        vm.prank(creator);
        nft.mintSingleNft(user, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
        assertEq(nft.ownerOf(4), user);

        // 6. Mint another collection NFT (token ID 5)
        vm.prank(creator);
        nft.mintToCollection(recipient, collectionId, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
        assertEq(nft.ownerOf(5), recipient);

        // Verify all token IDs are unique and sequential
        assertEq(nft.ownerOf(1), recipient);
        assertEq(nft.ownerOf(2), recipient);
        assertEq(nft.ownerOf(3), user);
        assertEq(nft.ownerOf(4), user);
        assertEq(nft.ownerOf(5), recipient);

        // Verify collection mapping
        assertEq(nft.tokenToCollection(1), 0); // Single NFT
        assertEq(nft.tokenToCollection(2), collectionId); // Collection NFT
        assertEq(nft.tokenToCollection(3), 0); // Social media NFT
        assertEq(nft.tokenToCollection(4), 0); // Single NFT
        assertEq(nft.tokenToCollection(5), collectionId); // Collection NFT
    }


    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    // function test_GetCollectionTokens() public {
    //     vm.prank(creator);
    //     nft.createCollection(NAME, SYMBOL, IMAGE, MAX_SUPPLY);

    //     vm.prank(creator);
    //     nft.mintToCollection(recipient, COLLECTION_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);

    //     uint256[] memory tokenIds = nft.getCollectionTokens(COLLECTION_ID);
    //     assertEq(tokenIds.length, 1);
    //     assertEq(tokenIds[0], TOKEN_ID);
    // }

    // function test_RevertIf_GetTokensForInvalidCollection() public {
    //     vm.expectRevert(VertixNFT.VertixNFT__InvalidCollection.selector);
    //     nft.getCollectionTokens(COLLECTION_ID);
    // }

    // function test_GetCollectionDetails() public {
    //     vm.prank(creator);
    //     nft.createCollection(NAME, SYMBOL, IMAGE, MAX_SUPPLY);

    //     (
    //         address collectionCreator,
    //         string memory name,
    //         string memory symbol,
    //         string memory image,
    //         uint256 maxSupply,
    //         uint256 currentSupply
    //     ) = nft.getCollectionDetails(COLLECTION_ID);

    //     assertEq(collectionCreator, creator);
    //     assertEq(name, NAME);
    //     assertEq(symbol, SYMBOL);
    //     assertEq(image, IMAGE);
    //     assertEq(maxSupply, MAX_SUPPLY);
    //     assertEq(currentSupply, 0);
    // }

    // function test_RevertIf_GetDetailsForInvalidCollection() public {
    //     vm.expectRevert(VertixNFT.VertixNFT__InvalidCollection.selector);
    //     nft.getCollectionDetails(COLLECTION_ID);
    // }

    /*//////////////////////////////////////////////////////////////
                    UPGRADE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade() public {
        // Create collection to test state preservation
        vm.prank(creator);
        nft.createCollection(NAME, SYMBOL, IMAGE, MAX_SUPPLY);

        // Deploy mock upgraded implementation
        vm.startPrank(owner);
        // Use a more robust deployment strategy with explicit address calculation
        VertixNFTV2Mock newImplementation = new VertixNFTV2Mock{salt: bytes32(uint256(1))}();

        // Upgrade the proxy
        nft.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();

        // Cast to V2 interface
        VertixNFTV2Mock upgradedNft = VertixNFTV2Mock(address(nft));

        // Verify state preservation
        assertEq(upgradedNft.owner(), owner);
        // (, string memory name,, string memory image, uint256 maxSupply,) =
        //     upgradedNft.getCollectionDetails(COLLECTION_ID);
        // assertEq(name, NAME);
        // assertEq(image, IMAGE);
        // assertEq(maxSupply, MAX_SUPPLY);

        // Test new functionality
        vm.prank(owner);
        upgradedNft.setNewFeature(100);
        assertEq(upgradedNft.getNewFeature(), 100);
    }

    function test_RevertIf_NonOwnerUpgrades() public {
        VertixNFT newImplementation = new VertixNFT();
        vm.prank(user);
        vm.expectRevert();
        nft.upgradeToAndCall(address(newImplementation), "");
    }
}
