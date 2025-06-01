// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {VertixNFT} from "../../src/VertixNFT.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {VertixGovernance} from "../../src/VertixGovernance.sol";

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
    VertixNFT public nftImplementation;
    VertixNFT public nft;

    address public owner = makeAddr("owner");
    address public creator = makeAddr("creator");
    address public user = makeAddr("user");
    address public verificationServer = makeAddr("verificationServer");
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
    // Create a wallet for verificationServer to get a valid private key
    (verificationServer, verificationServerPk) = makeAddrAndKey("verificationServer");

    // Create test addresses
    address marketplace = makeAddr("marketplace");
    address escrow = makeAddr("escrow");
    address feeRecipient = makeAddr("feeRecipient");

    vm.startPrank(owner);

    // Deploy governance implementation
    VertixGovernance governanceImpl = new VertixGovernance();

    // Deploy governance proxy and initialize
    ERC1967Proxy governanceProxy = new ERC1967Proxy(
        address(governanceImpl),
        abi.encodeWithSelector(
            VertixGovernance.initialize.selector,
            marketplace,
            escrow,
            feeRecipient,
            verificationServer
        )
    );
    VertixGovernance governance = VertixGovernance(address(governanceProxy));

    // Deploy NFT implementation
    nftImplementation = new VertixNFT();

    // Deploy NFT proxy and initialize with governance address
    ERC1967Proxy nftProxy = new ERC1967Proxy(
        address(nftImplementation),
        abi.encodeWithSelector(
            VertixNFT.initialize.selector,
            address(governance)  // Pass governance contract address
        )
    );
    nft = VertixNFT(address(nftProxy));

    vm.stopPrank();
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
        nft.createCollection(NAME, SYMBOL, IMAGE, MAX_SUPPLY);

        vm.prank(creator);
        vm.expectEmit(true, true, true, true);
        emit NFTMinted(recipient, TOKEN_ID, COLLECTION_ID, TOKEN_URI, METADATA_HASH, creator, ROYALTY_BPS);

        nft.mintToCollection(recipient, COLLECTION_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);

        // (,,,,, uint256 currentSupply) = nft.getCollectionDetails(COLLECTION_ID);
        // assertEq(currentSupply, 1);
        assertEq(nft.tokenToCollection(TOKEN_ID), COLLECTION_ID);
        assertEq(nft.ownerOf(TOKEN_ID), recipient);
        assertEq(nft.tokenURI(TOKEN_ID), TOKEN_URI);
        assertEq(nft.metadataHashes(TOKEN_ID), METADATA_HASH);
        (address royaltyRecipient, uint256 royaltyAmount) = nft.royaltyInfo(TOKEN_ID, 1 ether);
        assertEq(royaltyRecipient, creator);
        assertEq(royaltyAmount, (1 ether * ROYALTY_BPS) / 10000);
    }

    function test_RevertIf_MintToNonExistentCollection() public {
        vm.prank(creator);
        vm.expectRevert(VertixNFT.VertixNFT__InvalidCollection.selector);
        nft.mintToCollection(recipient, COLLECTION_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
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
        vm.expectEmit(true, true, true, true);
        emit NFTMinted(recipient, TOKEN_ID, 0, TOKEN_URI, METADATA_HASH, creator, ROYALTY_BPS);

        nft.mintSingleNFT(recipient, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);

        assertEq(nft.ownerOf(TOKEN_ID), recipient);
        assertEq(nft.tokenURI(TOKEN_ID), TOKEN_URI);
        assertEq(nft.metadataHashes(TOKEN_ID), METADATA_HASH);
        assertEq(nft.tokenToCollection(TOKEN_ID), 0);
        (address royaltyRecipient, uint256 royaltyAmount) = nft.royaltyInfo(TOKEN_ID, 1 ether);
        assertEq(royaltyRecipient, creator);
        assertEq(royaltyAmount, (1 ether * ROYALTY_BPS) / 10000);
    }

    function test_RevertIf_MintSingleNFTWithExcessiveRoyalty() public {
        uint96 excessiveRoyalty = uint96(nft.MAX_ROYALTY_BPS()) + 1;
        vm.prank(creator);
        vm.expectRevert(VertixNFT.VertixNFT__InvalidRoyaltyPercentage.selector);
        nft.mintSingleNFT(recipient, TOKEN_URI, METADATA_HASH, excessiveRoyalty);
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

        nft.mintSocialMediaNFT(recipient, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS, signature);

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
        nft.mintSocialMediaNFT(recipient, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS, signature);

        // Second mint with same social media ID
        vm.prank(user);
        vm.expectRevert(VertixNFT.VertixNFT__SocialMediaIdAlreadyUsed.selector);
        nft.mintSocialMediaNFT(recipient, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS, signature);
    }

    function test_RevertIf_MintSocialMediaNFTWithInvalidSignature() public {
        bytes32 messageHash = keccak256(abi.encodePacked(recipient, SOCIAL_MEDIA_ID));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(makeAddr("invalidSigner"))), ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(user);
        vm.expectRevert(VertixNFT.VertixNFT__InvalidSignature.selector);
        nft.mintSocialMediaNFT(recipient, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, ROYALTY_BPS, signature);
    }

    function test_RevertIf_MintSocialMediaNFTWithExcessiveRoyalty() public {
        bytes32 messageHash = keccak256(abi.encodePacked(recipient, SOCIAL_MEDIA_ID));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(verificationServer)), ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        uint96 excessiveRoyalty = uint96(nft.MAX_ROYALTY_BPS()) + 1;

        vm.prank(user);
        vm.expectRevert(VertixNFT.VertixNFT__InvalidRoyaltyPercentage.selector);
        nft.mintSocialMediaNFT(recipient, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, excessiveRoyalty, signature);
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
        VertixNFTV2Mock newImplementation = new VertixNFTV2Mock();

        // Upgrade the proxy
        nft.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();

        // Cast to V2 interface
        VertixNFTV2Mock upgradedNFT = VertixNFTV2Mock(address(nft));

        // Verify state preservation
        assertEq(upgradedNFT.owner(), owner);
        // (, string memory name,, string memory image, uint256 maxSupply,) =
        //     upgradedNFT.getCollectionDetails(COLLECTION_ID);
        // assertEq(name, NAME);
        // assertEq(image, IMAGE);
        // assertEq(maxSupply, MAX_SUPPLY);

        // Test new functionality
        vm.prank(owner);
        upgradedNFT.setNewFeature(100);
        assertEq(upgradedNFT.getNewFeature(), 100);
    }

    function test_RevertIf_NonOwnerUpgrades() public {
        VertixNFT newImplementation = new VertixNFT();
        vm.prank(user);
        vm.expectRevert();
        nft.upgradeToAndCall(address(newImplementation), "");
    }
}
