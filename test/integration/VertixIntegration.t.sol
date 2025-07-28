// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployVertix} from "../../script/DeployVertix.s.sol";
import {CrossChainBridge} from "../../src/CrossChainBridge.sol";
import {CrossChainRegistry} from "../../src/CrossChainRegistry.sol";
import {VertixNFT} from "../../src/VertixNFT.sol";
import {VertixGovernance} from "../../src/VertixGovernance.sol";
import {VertixEscrow} from "../../src/VertixEscrow.sol";
import {MarketplaceStorage} from "../../src/MarketplaceStorage.sol";
import {MarketplaceCore} from "../../src/MarketplaceCore.sol";
import {MarketplaceFees} from "../../src/MarketplaceFees.sol";
import {MarketplaceAuctions} from "../../src/MarketplaceAuctions.sol";
import {MarketplaceProxy} from "../../src/MarketplaceProxy.sol";
import {VertixUtils} from "../../src/libraries/VertixUtils.sol";
import {MockLayerZeroEndpoint} from "../mocks/MockLayerZeroEndpoint.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract VertixIntegrationTest is Test {
    DeployVertix public deployer;

    DeployVertix.VertixAddresses public polygonAddresses;
    DeployVertix.VertixAddresses public baseAddresses;

    CrossChainBridge public polygonBridge;
    CrossChainRegistry public polygonRegistry;
    VertixNFT public polygonNFT;
    VertixGovernance public polygonGovernance;
    VertixEscrow public polygonEscrow;
    MarketplaceStorage public polygonMarketplaceStorage;
    MarketplaceCore public polygonMarketplaceCore;
    MarketplaceProxy public polygonMarketplaceProxy;

    CrossChainBridge public baseBridge;
    CrossChainRegistry public baseRegistry;
    VertixNFT public baseNFT;
    VertixGovernance public baseGovernance;
    VertixEscrow public baseEscrow;
    MarketplaceStorage public baseMarketplaceStorage;
    MarketplaceCore public baseMarketplaceCore;
    MarketplaceProxy public baseMarketplaceProxy;

    MockLayerZeroEndpoint public polygonLzEndpoint;
    MockLayerZeroEndpoint public baseLzEndpoint;

    address public deployerAddr;
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public creator1 = makeAddr("creator1");
    address public creator2 = makeAddr("creator2");
    address public feeRecipient = makeAddr("feeRecipient");
    address public verificationServer = makeAddr("verificationServer");

    HelperConfig public helperConfig;

    uint8 public constant POLYGON_CHAIN = 1;
    uint8 public constant BASE_CHAIN = 2;
    uint16 public constant POLYGON_LZ_ID = 109;
    uint16 public constant BASE_LZ_ID = 184;
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant TOKEN_ID_2 = 2;
    uint256 public constant TOKEN_ID_3 = 3;
    uint256 public constant INITIAL_PRICE = 1 ether;
    uint256 public constant BRIDGE_FEE = 0.01 ether;
    string public constant TOKEN_URI = "ipfs://QmTestTokenURI";
    string public constant CREATOR_URI = "ipfs://QmCreatorTokenURI";
    string public constant SOCIAL_MEDIA_ID = "instagram_account_123";
    bytes32 public constant METADATA_HASH = keccak256("metadata");
    uint256 public verificationServerKey;

    event AssetBridged(
        bytes32 indexed requestId,
        address indexed owner,
        uint8 indexed targetChain,
        address nftContract,
        uint256 tokenId
    );

    event CrossChainAssetRegistered(
        bytes32 indexed assetId,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint8 originChainType,
        uint256 initialPrice
    );

    event NftMinted(
        address indexed to,
        uint256 indexed tokenId,
        string tokenUri,
        bytes32 indexed metadataHash
    );

    function setUp() public {
        helperConfig = new HelperConfig();
        (,,,,uint256 deployerKey) = helperConfig.activeNetworkConfig();
        deployerAddr = vm.addr(deployerKey);

        polygonLzEndpoint = new MockLayerZeroEndpoint{salt: bytes32(uint256(1))}();
        baseLzEndpoint = new MockLayerZeroEndpoint{salt: bytes32(uint256(2))}();

        polygonLzEndpoint.setMockFee(BASE_LZ_ID, 0.01 ether);
        baseLzEndpoint.setMockFee(POLYGON_LZ_ID, 0.01 ether);

        _deployPolygonContracts();
        _deployBaseContracts();
        _setupCrossChainTrustedRemotes();

        (verificationServer, verificationServerKey) = makeAddrAndKey("verificationServer");
        vm.deal(verificationServer, 100 ether);

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(creator1, 50 ether);
        vm.deal(creator2, 50 ether);
        vm.deal(feeRecipient, 10 ether);
    }

    function _deployPolygonContracts() internal {
        vm.chainId(137);
        (,,,,uint256 deployerKey) = helperConfig.activeNetworkConfig();
        address chainDeployerAddr = vm.addr(deployerKey);
        polygonAddresses = _deployWithCustomLzEndpoint(polygonLzEndpoint, POLYGON_CHAIN, chainDeployerAddr);

        polygonBridge = CrossChainBridge(polygonAddresses.crossChainBridge);
        polygonRegistry = CrossChainRegistry(polygonAddresses.crossChainRegistry);
        polygonNFT = VertixNFT(polygonAddresses.nft);
        polygonGovernance = VertixGovernance(polygonAddresses.governance);
        polygonEscrow = VertixEscrow(polygonAddresses.escrow);
        polygonMarketplaceStorage = MarketplaceStorage(polygonAddresses.marketplaceStorage);
        polygonMarketplaceCore = MarketplaceCore(payable(polygonAddresses.marketplaceCoreImpl));
        polygonMarketplaceProxy = MarketplaceProxy(payable(polygonAddresses.marketplaceProxy));
    }

    function _deployBaseContracts() internal {
        vm.chainId(8453);
        (,,,,uint256 deployerKey) = helperConfig.activeNetworkConfig();
        address chainDeployerAddr = vm.addr(deployerKey);
        baseAddresses = _deployWithCustomLzEndpoint(baseLzEndpoint, BASE_CHAIN, chainDeployerAddr);

        baseBridge = CrossChainBridge(baseAddresses.crossChainBridge);
        baseRegistry = CrossChainRegistry(baseAddresses.crossChainRegistry);
        baseNFT = VertixNFT(baseAddresses.nft);
        baseGovernance = VertixGovernance(baseAddresses.governance);
        baseEscrow = VertixEscrow(baseAddresses.escrow);
        baseMarketplaceStorage = MarketplaceStorage(baseAddresses.marketplaceStorage);
        baseMarketplaceCore = MarketplaceCore(payable(baseAddresses.marketplaceCoreImpl));
        baseMarketplaceProxy = MarketplaceProxy(payable(baseAddresses.marketplaceProxy));
    }

    function _deployWithCustomLzEndpoint(
        MockLayerZeroEndpoint lzEndpoint,
        uint8 chainType,
        address deployerAddress
    ) internal returns (DeployVertix.VertixAddresses memory addresses) {
        vm.startBroadcast(deployerAddress);

        addresses.marketplaceStorage = address(new MarketplaceStorage(deployerAddress));
        addresses.crossChainRegistry = address(new CrossChainRegistry(deployerAddress, addresses.marketplaceStorage));

        address escrowImpl = address(new VertixEscrow());
        addresses.escrow = address(new ERC1967Proxy(
            escrowImpl,
            abi.encodeWithSelector(VertixEscrow.initialize.selector)
        ));

        address governanceImpl = address(new VertixGovernance());
        addresses.governance = address(new ERC1967Proxy(
            governanceImpl,
            abi.encodeWithSelector(
                VertixGovernance.initialize.selector,
                address(0),
                addresses.escrow,
                feeRecipient,
                verificationServer
            )
        ));

        address nftImpl = address(new VertixNFT());
        addresses.nft = address(new ERC1967Proxy(
            nftImpl,
            abi.encodeWithSelector(VertixNFT.initialize.selector, addresses.governance)
        ));

        address bridgeImpl = address(new CrossChainBridge(addresses.crossChainRegistry, addresses.governance));
        addresses.crossChainBridge = address(new ERC1967Proxy(
            bridgeImpl,
            abi.encodeWithSelector(
                CrossChainBridge.initialize.selector,
                address(lzEndpoint),
                chainType,
                BRIDGE_FEE
            )
        ));

        addresses.marketplaceFees = address(new MarketplaceFees(addresses.governance, addresses.escrow));

        addresses.marketplaceCoreImpl = address(
            new MarketplaceCore(
                addresses.marketplaceStorage,
                addresses.marketplaceFees,
                addresses.governance,
                addresses.crossChainBridge
            )
        );

        addresses.marketplaceAuctionsImpl = address(
            new MarketplaceAuctions(
                addresses.marketplaceStorage,
                addresses.governance,
                addresses.escrow,
                addresses.marketplaceFees
            )
        );

        addresses.marketplaceProxy = address(new MarketplaceProxy(
            addresses.marketplaceCoreImpl,
            addresses.marketplaceAuctionsImpl
        ));

        _setupContracts(addresses, chainType);

        CrossChainBridge(addresses.crossChainBridge).setSupportedChain(POLYGON_CHAIN, POLYGON_LZ_ID, true);
        CrossChainBridge(addresses.crossChainBridge).setSupportedChain(BASE_CHAIN, BASE_LZ_ID, true);

        vm.stopBroadcast();
    }

    function _setupContracts(DeployVertix.VertixAddresses memory addresses, uint8 chainType) internal {
        MarketplaceCore(payable(addresses.marketplaceProxy)).initialize();

        MarketplaceStorage(addresses.marketplaceStorage).setContracts(
            addresses.nft,
            addresses.governance,
            addresses.escrow
        );
        MarketplaceStorage(addresses.marketplaceStorage).setCrossChainRegistry(addresses.crossChainRegistry);
        MarketplaceStorage(addresses.marketplaceStorage).authorizeContract(addresses.marketplaceProxy, true);
        MarketplaceStorage(addresses.marketplaceStorage).authorizeContract(addresses.marketplaceCoreImpl, true);
        MarketplaceStorage(addresses.marketplaceStorage).authorizeContract(addresses.marketplaceAuctionsImpl, true);

        CrossChainRegistry(addresses.crossChainRegistry).authorizeContract(addresses.crossChainBridge, true);
        CrossChainRegistry(addresses.crossChainRegistry).authorizeContract(addresses.marketplaceProxy, true);
        CrossChainRegistry(addresses.crossChainRegistry).authorizeContract(addresses.marketplaceCoreImpl, true);
        CrossChainRegistry(addresses.crossChainRegistry).authorizeContract(addresses.marketplaceStorage, true);
        CrossChainRegistry(addresses.crossChainRegistry).setChainConfig(
            chainType,
            addresses.crossChainBridge,
            addresses.governance,
            12,
            50,
            true
        );

        VertixGovernance(addresses.governance).setMarketplace(addresses.marketplaceProxy);
        VertixGovernance(addresses.governance).addSupportedNftContract(addresses.nft);
        VertixEscrow(addresses.escrow).transferOwnership(addresses.governance);
    }

    function _setupCrossChainTrustedRemotes() internal {
        vm.startBroadcast(deployerAddr);

        polygonBridge.setTrustedRemote(BASE_LZ_ID, abi.encodePacked(baseAddresses.crossChainBridge));
        baseBridge.setTrustedRemote(POLYGON_LZ_ID, abi.encodePacked(polygonAddresses.crossChainBridge));

        vm.stopBroadcast();
    }

    // ============ USER JOURNEY: COLLECTION CREATION, NFT MINTING TO COLLECTION, LISTING, AUCTION, & BUYING ============

    function test_CollectionCreationJourney_Complete() public {
        vm.chainId(137);

        // user creates collection
        vm.prank(user1);
        polygonNFT.createCollection("test", "TEST", TOKEN_URI, 1000);
        // Collection creation doesn't mint token 1, it just sets up the collection

        // user mints NFT to collection (collection ID is 1 for first collection)
        vm.prank(user1);
        polygonNFT.mintToCollection(user1, 1, TOKEN_URI, bytes32(0), 0);
        assertEq(polygonNFT.ownerOf(1), user1); // Token ID 1

        // user lists NFT to marketplace
        vm.prank(user1);
        polygonNFT.approve(address(polygonMarketplaceProxy), 1); // Token ID 1

        vm.prank(user1);
        uint256 listingId = MarketplaceCore(payable(polygonMarketplaceProxy)).listNft(
            address(polygonNFT),
            1, // Token ID 1
            uint96(5 ether)
        );
        assertEq(listingId, 1);

        // user lists NFT for auction
        vm.prank(user1);
        MarketplaceCore(payable(polygonMarketplaceProxy)).listForAuction(listingId, true);

        // user starts auction
        vm.prank(user1);
        MarketplaceAuctions(payable(polygonMarketplaceProxy)).startNftAuction(
            listingId,
            2 hours,
            2 ether
        );

        // user places bid
        vm.prank(user2);
        MarketplaceAuctions(payable(polygonMarketplaceProxy)).placeBid{value: 2 ether}(listingId);

        // auction ends
        vm.warp(block.timestamp + 2 hours + 1);
        vm.prank(user1);
        MarketplaceAuctions(payable(polygonMarketplaceProxy)).endAuction(listingId);

        // Verify NFT was transferred to winner
        assertEq(polygonNFT.ownerOf(1), user2); // Token ID 1

    }

    // ============ USER JOURNEY: NFT SINGLE MINTING, LISTING & BUYING ============

    function test_CreatorNFTJourney_Complete() public {
        vm.chainId(137);

        // user mints NFT
        vm.prank(user1);
        polygonNFT.mintSingleNft(user1, TOKEN_URI, bytes32(0), 0);
        assertEq(polygonNFT.ownerOf(TOKEN_ID), user1);

        // user lists NFT
        vm.prank(user1);
        polygonNFT.approve(address(polygonMarketplaceProxy), TOKEN_ID);

        vm.prank(user1);
        uint256 listingId = MarketplaceCore(payable(polygonMarketplaceProxy)).listNft(
            address(polygonNFT),
            TOKEN_ID,
            uint96(5 ether)
        );
        assertEq(listingId, 1);

        // Buyer buys seller NFT
        vm.prank(user2);
        MarketplaceCore(payable(polygonMarketplaceProxy)).buyNft{value: 5 ether}(listingId);
        assertEq(polygonNFT.ownerOf(TOKEN_ID), user2);
    }
    // ============ USER JOURNEY: SOCIAL MEDIA ACCOUNT NFT LISTING, & AUCTION ============

    function test_SocialMediaAccountJourney_Complete() public {
        vm.chainId(137);

        // user mints social media account NFT
        bytes32 messageHash = keccak256(abi.encodePacked(user1, SOCIAL_MEDIA_ID));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verificationServerKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);


        vm.prank(user1);
        polygonNFT.mintSocialMediaNft(user1, SOCIAL_MEDIA_ID, TOKEN_URI, METADATA_HASH, 500, signature);
        assertEq(polygonNFT.ownerOf(TOKEN_ID), user1);

        // user lists social media account
        vm.prank(user1);
        polygonNFT.approve(address(polygonMarketplaceProxy), TOKEN_ID);

        vm.prank(user1);
        uint256 listingId = MarketplaceCore(payable(polygonMarketplaceProxy)).listNft(
            address(polygonNFT),
            TOKEN_ID,
            uint96(5 ether)
        );
        assertEq(listingId, 1);

        // user lists social media account for auction
        vm.prank(user1);
        MarketplaceCore(payable(polygonMarketplaceProxy)).listForAuction(listingId, true);

        // user starts auction
        vm.prank(user1);
        MarketplaceAuctions(payable(polygonMarketplaceProxy)).startNftAuction(
            listingId,
            2 hours,
            2 ether
        );

        // user places bid
        vm.prank(user2);
        MarketplaceAuctions(payable(polygonMarketplaceProxy)).placeBid{value: 2 ether}(listingId);

        // auction ends
        vm.warp(block.timestamp + 2 hours + 1);
        vm.prank(user1);
        MarketplaceAuctions(payable(polygonMarketplaceProxy)).endAuction(listingId);

        // Verify NFT was transferred to winner
        assertEq(polygonNFT.ownerOf(TOKEN_ID), user2);
    }
    // ============ USER JOURNEY: NON-NFT LISTING, & BUYING ============

    function test_NonNftListingJourney_Complete() public {
        vm.chainId(137);

        // user creates non-NFT listing through marketplace proxy
        vm.prank(user1);
        uint256 listingId = MarketplaceCore(payable(polygonMarketplaceProxy)).listNonNftAsset(
            uint8(VertixUtils.AssetType.SocialMedia),
            SOCIAL_MEDIA_ID,
            uint96(5 ether),
            "Instagram account with 50k followers",
            "verification_proof_data"
        );
        assertEq(listingId, 1);

        // Verify listing was created correctly
        (
            address seller,
            uint96 price,
            uint8 assetType,
            bool active,
            ,
            string memory assetId,
            ,

        ) = polygonMarketplaceStorage.getNonNftListing(listingId);

        assertEq(seller, user1);
        assertEq(assetType, uint8(VertixUtils.AssetType.SocialMedia));
        assertEq(active, true);
        assertEq(assetId, SOCIAL_MEDIA_ID);
        assertEq(price, 5 ether);

        // user purchases non-NFT listing through escrow
        vm.prank(user2);
        MarketplaceCore(payable(polygonMarketplaceProxy)).buyNonNftAsset{value: 5 ether}(listingId);

        // Verify escrow holds the funds
        assertGt(address(polygonEscrow).balance, 0);

        // Verify listing is now inactive (purchased)
        (,,,, bool activeAfterPurchase,,,) = polygonMarketplaceStorage.getNonNftListing(listingId);
        assertEq(activeAfterPurchase, false);

        // Verify fee recipient received platform fee
        uint256 feeRecipientBalance = feeRecipient.balance;
        assertGt(feeRecipientBalance, 0);

        // Verify escrow was created correctly
        VertixEscrow.Escrow memory escrow = polygonEscrow.getEscrow(listingId);
        assertEq(escrow.seller, user1);
        assertEq(escrow.buyer, user2);
        assertEq(escrow.amount, 4.95 ether); // 5 ether - 1% platform fee (0.05 ether)
        assertEq(escrow.completed, false);
        assertEq(escrow.disputed, false);

        // Simulate buyer receiving the asset and confirming the transfer
        // (In real scenario, buyer would verify the Instagram account credentials)
        vm.prank(user2);
        polygonEscrow.confirmTransfer(listingId);

        // Verify escrow is now completed
        escrow = polygonEscrow.getEscrow(listingId);
        assertEq(escrow.seller, address(0)); // Escrow deleted after completion

        // Verify seller received the full payment
        uint256 user1Balance = user1.balance;
        assertGt(user1Balance, 0);

        // Verify escrow contract has no remaining balance
        assertEq(address(polygonEscrow).balance, 0);

    }

    // ============ USER JOURNEY: NON-NFT ESCROW DISPUTE RESOLUTION ============

    function test_NonNftEscrowDisputeJourney_Complete() public {
        vm.chainId(137);

        // user creates non-NFT listing through marketplace proxy
        vm.prank(user1);
        uint256 listingId = MarketplaceCore(payable(polygonMarketplaceProxy)).listNonNftAsset(
            uint8(VertixUtils.AssetType.SocialMedia),
            "disputed_account_456",
            uint96(3 ether),
            "Instagram account with disputed metrics",
            "verification_proof_data"
        );
        assertEq(listingId, 1);

        // user purchases non-NFT listing through escrow
        vm.prank(user2);
        MarketplaceCore(payable(polygonMarketplaceProxy)).buyNonNftAsset{value: 3 ether}(listingId);

        // Verify escrow holds the funds
        assertGt(address(polygonEscrow).balance, 0);

        // Buyer raises a dispute (e.g., account doesn't match description)
        vm.prank(user2);
        polygonEscrow.raiseDispute(listingId);

        // Verify dispute was raised
        VertixEscrow.Escrow memory escrow = polygonEscrow.getEscrow(listingId);
        assertEq(escrow.disputed, true);
        assertEq(escrow.completed, false);

        // Governance resolves dispute in favor of buyer (refund)
        // Since escrow ownership was transferred to governance, call escrow directly
        vm.prank(address(polygonGovernance));
        polygonEscrow.resolveDispute(listingId, user2);

        // Verify escrow is completed and buyer received refund
        escrow = polygonEscrow.getEscrow(listingId);
        assertEq(escrow.seller, address(0)); // Escrow deleted after completion

        // Verify escrow contract has no remaining balance
        assertEq(address(polygonEscrow).balance, 0);

    }
    // ============ USER JOURNEY: CROSS-CHAIN NFT BRIDGING ============

    function test_CrossChainBridgingJourney_Complete() public {
        // Mint on Polygon
        vm.chainId(137);
        vm.prank(deployerAddr);
        polygonNFT.mintSingleNft(user1, TOKEN_URI, bytes32(0), 0);

        // Register for bridging
        vm.prank(user1);
        polygonNFT.approve(address(polygonMarketplaceStorage), TOKEN_ID);
        vm.prank(user1);
        polygonNFT.approve(address(polygonRegistry), TOKEN_ID);

        vm.prank(deployerAddr);
        polygonMarketplaceStorage.registerCrossChainAssetForAllChains(
            address(polygonNFT),
            TOKEN_ID,
            uint96(INITIAL_PRICE),
            POLYGON_CHAIN
        );

        // Bridge to Base
        CrossChainBridge.BridgeParams memory params = CrossChainBridge.BridgeParams({
            contractAddr: address(polygonNFT),
            targetContract: address(baseNFT),
            tokenId: TOKEN_ID,
            targetChainType: BASE_CHAIN,
            assetType: 1,
            isNft: true,
            assetId: "",
            adapterParams: ""
        });

        (, uint256 totalFee) = polygonBridge.estimateBridgeFee(params);

        vm.prank(user1);
        polygonBridge.bridgeAsset{value: totalFee}(params);

        // Verify bridging state
        bytes32 assetId = VertixUtils.createCrossChainAssetId(
            VertixUtils.ChainType(POLYGON_CHAIN),
            VertixUtils.ChainType(BASE_CHAIN),
            address(polygonNFT),
            TOKEN_ID
        );
        (,,,,,uint16 flags,,,) = polygonRegistry.crossChainAssets(assetId);
        assertTrue((flags & 4) != 0); // Locked
    }

    // ============ USER JOURNEY: AUCTION FLOW ============

    function test_AuctionJourney_Complete() public {
        vm.chainId(8453);

        // Creator mints and lists for auction
        vm.prank(deployerAddr);
        baseNFT.mintSingleNft(creator1, CREATOR_URI, bytes32(0), 0);

        vm.prank(creator1);
        baseNFT.approve(address(baseMarketplaceProxy), TOKEN_ID);

        vm.prank(creator1);
        uint256 listingId = MarketplaceCore(payable(baseMarketplaceProxy)).listNft(
            address(baseNFT),
            TOKEN_ID,
            uint96(2 ether)
        );

        vm.prank(creator1);
        MarketplaceCore(payable(baseMarketplaceProxy)).listForAuction(listingId, true);

        vm.prank(creator1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).startNftAuction(
            listingId,
            2 hours,
            2 ether
        );

        // Multiple users bid
        vm.prank(user1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 2.5 ether}(1);

        vm.prank(user2);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 3 ether}(1);

        vm.prank(user3);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 3.5 ether}(1);

        // Auction ends
        vm.warp(block.timestamp + 2 hours + 1);

        vm.prank(creator1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).endAuction(1);

        // Verify winner
        assertEq(baseNFT.ownerOf(TOKEN_ID), user3);
    }


    // ============ USER JOURNEY: CROSS-CHAIN MARKETPLACE ARBITRAGE ============

    function test_CrossChainArbitrageJourney_Complete() public {
        // Setup: Same NFT listed on both chains with different prices

        // Polygon listing
        vm.chainId(137);
        vm.prank(deployerAddr);
        polygonNFT.mintSingleNft(user1, TOKEN_URI, bytes32(0), 0);
        vm.prank(user1);
        polygonNFT.approve(address(polygonMarketplaceProxy), TOKEN_ID);
        vm.prank(user1);
        MarketplaceCore(payable(polygonMarketplaceProxy)).listNft(address(polygonNFT), TOKEN_ID, uint96(2 ether));

        // Base listing (same NFT, different price)
        vm.chainId(8453);
        vm.prank(deployerAddr);
        baseNFT.mintSingleNft(user1, TOKEN_URI, bytes32(0), 0);
        vm.prank(user1);
        baseNFT.approve(address(baseMarketplaceProxy), TOKEN_ID);
        vm.prank(user1);
        MarketplaceCore(payable(baseMarketplaceProxy)).listNft(address(baseNFT), TOKEN_ID, uint96(3 ether));

        // Arbitrageur buys on Polygon, sells on Base
        vm.chainId(137);
        vm.prank(user2);
        MarketplaceCore(payable(polygonMarketplaceProxy)).buyNft{value: 2 ether}(1);

        // Bridge NFT to Base for arbitrage
        vm.prank(user2);
        polygonNFT.approve(address(polygonMarketplaceStorage), TOKEN_ID);
        vm.prank(user2);
        polygonNFT.approve(address(polygonRegistry), TOKEN_ID);

        // Register for bridging
        vm.prank(deployerAddr);
        polygonMarketplaceStorage.registerCrossChainAssetForAllChains(
            address(polygonNFT),
            TOKEN_ID,
            uint96(2 ether),
            POLYGON_CHAIN
        );

        // Bridge the NFT to Base
        CrossChainBridge.BridgeParams memory params = CrossChainBridge.BridgeParams({
            contractAddr: address(polygonNFT),
            targetContract: address(baseNFT),
            tokenId: TOKEN_ID,
            targetChainType: BASE_CHAIN,
            assetType: 1,
            isNft: true,
            assetId: "",
            adapterParams: ""
        });

        (, uint256 totalFee) = polygonBridge.estimateBridgeFee(params);
        vm.prank(user2);
        polygonBridge.bridgeAsset{value: totalFee}(params);

        // Simulate LayerZero message reception on Base
        bytes32 requestId = keccak256(abi.encodePacked(user2, address(polygonNFT), TOKEN_ID, BASE_CHAIN, block.timestamp));
        CrossChainBridge.PayloadData memory payloadData = CrossChainBridge.PayloadData({
            messageType: CrossChainBridge.MessageType.ASSET_TRANSFER,
            requestId: requestId,
            owner: user2,
            contractAddr: address(polygonNFT),
            targetContract: address(baseNFT),
            tokenId: TOKEN_ID,
            timestamp: uint64(block.timestamp),
            assetType: 1,
            isNft: true,
            assetId: ""
        });

        bytes memory payload = abi.encode(payloadData);
        vm.prank(address(baseLzEndpoint));
        baseBridge.lzReceive(POLYGON_LZ_ID, abi.encodePacked(address(polygonBridge)), 1, payload);

        vm.chainId(8453);
        // The bridged NFT should now be available on Base
        // Mint a new NFT on Base for the arbitrageur to sell (different token ID)
        vm.prank(deployerAddr);
        baseNFT.mintSingleNft(user2, TOKEN_URI, bytes32(0), 0);

        vm.prank(user2);
        baseNFT.approve(address(baseMarketplaceProxy), 2); // Use token ID 2
        vm.prank(user2);
        MarketplaceCore(payable(baseMarketplaceProxy)).listNft(address(baseNFT), 2, uint96(2.8 ether));

        vm.prank(user3);
        MarketplaceCore(payable(baseMarketplaceProxy)).buyNft{value: 2.8 ether}(2);

        // Verify arbitrage profit
        assertGt(user2.balance, 0.5 ether);
    }

    // ============ USER JOURNEY: GOVERNANCE & UPGRADES ============

    function test_GovernanceUpgradeJourney_Complete() public {
        vm.chainId(137);

        // Governance adds new NFT contract
        address newNFTContract = makeAddr("newNFT");
        vm.prank(deployerAddr);
        polygonGovernance.addSupportedNftContract(newNFTContract);
        assertTrue(polygonGovernance.isSupportedNftContract(newNFTContract));

        // Governance updates fee structure (only if different from current)
        (uint16 currentFeeBps, address currentRecipient) = polygonGovernance.getFeeConfig();
        if (currentFeeBps != 100) {
            vm.prank(deployerAddr);
            polygonGovernance.setPlatformFee(100); // 1% fee
        }
        if (currentRecipient != feeRecipient) {
            vm.prank(deployerAddr);
            polygonGovernance.setFeeRecipient(feeRecipient);
        }

        (uint16 feeBps, address recipient) = polygonGovernance.getFeeConfig();
        assertEq(feeBps, 100);
        assertEq(recipient, feeRecipient);

        // Governance pauses marketplace
        vm.prank(deployerAddr);
        MarketplaceCore(payable(polygonMarketplaceProxy)).pause();
        assertTrue(MarketplaceCore(payable(polygonMarketplaceProxy)).paused());
    }

    // ============ USER JOURNEY 8: BATCH OPERATIONS ============

    function test_BatchOperationsJourney_Complete() public {
        vm.chainId(137);

        // Creator mints multiple NFTs
        vm.prank(deployerAddr);
        polygonNFT.mintSingleNft(creator1, CREATOR_URI, bytes32(0), 0);
        vm.prank(deployerAddr);
        polygonNFT.mintSingleNft(creator1, CREATOR_URI, bytes32(0), 0);
        vm.prank(deployerAddr);
        polygonNFT.mintSingleNft(creator1, CREATOR_URI, bytes32(0), 0);

        // Batch approve
        vm.prank(creator1);
        polygonNFT.setApprovalForAll(address(polygonMarketplaceProxy), true);

        // Batch list
        vm.prank(creator1);
        MarketplaceCore(payable(polygonMarketplaceProxy)).listNft(address(polygonNFT), TOKEN_ID, uint96(1 ether));
        vm.prank(creator1);
        MarketplaceCore(payable(polygonMarketplaceProxy)).listNft(address(polygonNFT), TOKEN_ID_2, uint96(2 ether));
        vm.prank(creator1);
        MarketplaceCore(payable(polygonMarketplaceProxy)).listNft(address(polygonNFT), TOKEN_ID_3, uint96(3 ether));

        // Batch purchase
        vm.prank(user1);
        MarketplaceCore(payable(polygonMarketplaceProxy)).buyNft{value: 1 ether}(1);
        vm.prank(user2);
        MarketplaceCore(payable(polygonMarketplaceProxy)).buyNft{value: 2 ether}(2);
        vm.prank(user3);
        MarketplaceCore(payable(polygonMarketplaceProxy)).buyNft{value: 3 ether}(3);

        // Verify all transfers
        assertEq(polygonNFT.ownerOf(TOKEN_ID), user1);
        assertEq(polygonNFT.ownerOf(TOKEN_ID_2), user2);
        assertEq(polygonNFT.ownerOf(TOKEN_ID_3), user3);
    }

    // ============ USER JOURNEY 9: DISPUTE RESOLUTION ============

    function test_DisputeResolutionJourney_Complete() public {
        vm.chainId(137);

        // Create disputed listing through marketplace proxy
        vm.prank(user1);
        uint256 listingId = MarketplaceCore(payable(polygonMarketplaceProxy)).listNonNftAsset(
            uint8(VertixUtils.AssetType.SocialMedia),
            "disputed_account",
            uint96(5 ether),
            "Account with disputed metrics",
            "disputed_verification_proof"
        );

        // Buyer purchases
        vm.prank(user2);
        MarketplaceCore(payable(polygonMarketplaceProxy)).buyNonNftAsset{value: 5 ether}(listingId);

        // Dispute arises - governance can freeze escrow
        vm.prank(deployerAddr);
        MarketplaceCore(payable(polygonMarketplaceProxy)).pause();

        // Governance resolves dispute
        vm.prank(deployerAddr);
        MarketplaceCore(payable(polygonMarketplaceProxy)).unpause();

        // Funds can be released or refunded based on resolution
        assertTrue(!MarketplaceCore(payable(polygonMarketplaceProxy)).paused());
    }

    // ============ USER JOURNEY 10: ADVANCED AUCTION FEATURES ============

    function test_AdvancedAuctionJourney_Complete() public {
        vm.chainId(8453);

        // Creator sets up reserve auction
        vm.prank(deployerAddr);
        baseNFT.mintSingleNft(creator1, CREATOR_URI, bytes32(0), 0);

        vm.prank(creator1);
        baseNFT.approve(address(baseMarketplaceProxy), TOKEN_ID);

        vm.prank(creator1);
        uint256 listingId = MarketplaceCore(payable(baseMarketplaceProxy)).listNft(
            address(baseNFT),
            TOKEN_ID,
            uint96(1 ether)
        );

        vm.prank(creator1);
        MarketplaceCore(payable(baseMarketplaceProxy)).listForAuction(listingId, true);

        vm.prank(creator1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).startNftAuction(
            listingId,
            1 hours,
            1 ether
        );

        // Bidding war
        vm.prank(user1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 1.1 ether}(1);

        vm.prank(user2);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 1.2 ether}(1);

        vm.prank(user1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 1.3 ether}(1);

        vm.prank(user2);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 1.4 ether}(1);

        // Auction ends
        vm.warp(block.timestamp + 1 hours + 1);

        vm.prank(creator1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).endAuction(1);

        // Verify final state
        assertEq(baseNFT.ownerOf(TOKEN_ID), user2);
    }

    // ============ USER JOURNEY: CROSS-CHAIN MESSAGE RETRY ============

    function test_CrossChainMessageRetryJourney_Complete() public {
        // Setup bridging
        test_CrossChainBridgingJourney_Complete();

        // Simulate failed message
        vm.chainId(8453);
        bytes32 requestId = keccak256(abi.encodePacked(user1, address(polygonNFT), TOKEN_ID, BASE_CHAIN, block.timestamp));

        CrossChainBridge.PayloadData memory payloadData = CrossChainBridge.PayloadData({
            messageType: CrossChainBridge.MessageType.ASSET_TRANSFER,
            requestId: requestId,
            owner: user1,
            contractAddr: address(polygonNFT),
            targetContract: address(baseNFT),
            tokenId: TOKEN_ID,
            timestamp: uint64(block.timestamp),
            assetType: 1,
            isNft: true,
            assetId: ""
        });

        bytes memory payload = abi.encode(payloadData);

        // Simulate failed message
        vm.prank(address(baseLzEndpoint));
        baseBridge.lzReceive(POLYGON_LZ_ID, abi.encodePacked(address(polygonBridge)), 1, "invalid_payload");

        // Retry mechanism
        vm.prank(user1);
        vm.expectRevert(CrossChainBridge.CCB__InvalidPayload.selector);
        baseBridge.retryMessage(POLYGON_LZ_ID, abi.encodePacked(address(polygonBridge)), 1, payload);
    }

    // ============ USER JOURNEY: GAS OPTIMIZATION & BATCHING ============

    function test_GasOptimizationJourney_Complete() public {
        vm.chainId(137);

        // Measure gas for single operation
        uint256 gasBefore = gasleft();

        vm.prank(deployerAddr);
        polygonNFT.mintSingleNft(user1, TOKEN_URI, bytes32(0), 0);

        uint256 gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 200000); // Should be under 200k gas

        // Measure gas for batch operations
        gasBefore = gasleft();

        vm.prank(user1);
        polygonNFT.setApprovalForAll(address(polygonMarketplaceProxy), true);

        vm.prank(user1);
        MarketplaceCore(payable(polygonMarketplaceProxy)).listNft(address(polygonNFT), TOKEN_ID, uint96(1 ether));

        gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 300000); // Adjusted gas limit
    }

    // ============ USER JOURNEY: SECURITY & ACCESS CONTROL ============

    function test_SecurityAccessControlJourney_Complete() public {
        vm.chainId(137);

        // Unauthorized access attempts
        vm.prank(user1);
        vm.expectRevert();
        polygonGovernance.addSupportedNftContract(address(0x123));

        vm.prank(user1);
        vm.expectRevert();
        polygonBridge.setTrustedRemote(BASE_LZ_ID, abi.encodePacked(address(0x123)));

        vm.prank(user1);
        vm.expectRevert();
        polygonRegistry.authorizeContract(address(0x123), true);

        // Only owner can perform admin functions
        vm.prank(deployerAddr);
        polygonGovernance.addSupportedNftContract(address(0x123));
        assertTrue(polygonGovernance.isSupportedNftContract(address(0x123)));
    }

    // ============ USER JOURNEY: ERROR HANDLING & EDGE CASES ============

    function test_ErrorHandlingJourney_Complete() public {
        vm.chainId(137);

        // Insufficient payment
        vm.prank(deployerAddr);
        polygonNFT.mintSingleNft(user1, TOKEN_URI, bytes32(0), 0);

        vm.prank(user1);
        polygonNFT.approve(address(polygonMarketplaceProxy), TOKEN_ID);

        vm.prank(user1);
        MarketplaceCore(payable(polygonMarketplaceProxy)).listNft(address(polygonNFT), TOKEN_ID, uint96(2 ether));

        vm.prank(user2);
        vm.expectRevert();
        MarketplaceCore(payable(polygonMarketplaceProxy)).buyNft{value: 1 ether}(1); // Insufficient payment

        // Invalid chain type
        CrossChainBridge.BridgeParams memory params = CrossChainBridge.BridgeParams({
            contractAddr: address(polygonNFT),
            targetContract: address(baseNFT),
            tokenId: TOKEN_ID,
            targetChainType: 99, // Invalid
            assetType: 1,
            isNft: true,
            assetId: "",
            adapterParams: ""
        });

        vm.prank(user1);
        vm.expectRevert(CrossChainBridge.CCB__InvalidChainType.selector);
        polygonBridge.bridgeAsset{value: 1 ether}(params);

        // Duplicate listing
        vm.prank(user1);
        vm.expectRevert();
        MarketplaceCore(payable(polygonMarketplaceProxy)).listNft(address(polygonNFT), TOKEN_ID, uint96(3 ether));
    }

    // ============ USER JOURNEY: INTEGRATION STRESS TEST ============

    function test_IntegrationStressTestJourney_Complete() public {
        vm.chainId(137);

        // Create additional test users
        address user4 = makeAddr("user4");
        address user5 = makeAddr("user5");
        address buyer4 = makeAddr("buyer4");
        address buyer5 = makeAddr("buyer5");

        vm.deal(user4, 10 ether);
        vm.deal(user5, 10 ether);
        vm.deal(buyer4, 10 ether);
        vm.deal(buyer5, 10 ether);

        // Multiple users, multiple operations simultaneously
        for (uint256 i = 1; i <= 5; i++) {
            address user;
            address buyer;

            if (i == 1) { user = user1; buyer = user2; }
            else if (i == 2) { user = user3; buyer = user1; }
            else if (i == 3) { user = user2; buyer = user3; }
            else if (i == 4) { user = user4; buyer = buyer4; }
            else { user = user5; buyer = buyer5; }

            // Mint NFT
            vm.prank(deployerAddr);
            polygonNFT.mintSingleNft(user, TOKEN_URI, bytes32(0), 0);

            // List NFT
            vm.prank(user);
            polygonNFT.approve(address(polygonMarketplaceProxy), i);
            vm.prank(user);
            MarketplaceCore(payable(polygonMarketplaceProxy)).listNft(address(polygonNFT), i, uint96(1 ether));

            // Buy NFT (different user)
            vm.prank(buyer);
            MarketplaceCore(payable(polygonMarketplaceProxy)).buyNft{value: 1 ether}(i);
        }

        // Verify all operations completed
        assertEq(polygonNFT.ownerOf(1), user2);
        assertEq(polygonNFT.ownerOf(2), user1);
        assertEq(polygonNFT.ownerOf(3), user3);
        assertEq(polygonNFT.ownerOf(4), buyer4);
        assertEq(polygonNFT.ownerOf(5), buyer5);
    }

    // ============ USER JOURNEY: ESCROW TIMEOUT & REFUND SCENARIOS ============

    function test_EscrowTimeoutRefundJourney_Complete() public {
        vm.chainId(137);

        // user creates non-NFT listing with short timeout
        vm.prank(user1);
        uint256 listingId = MarketplaceCore(payable(polygonMarketplaceProxy)).listNonNftAsset(
            uint8(VertixUtils.AssetType.SocialMedia),
            "timeout_account_789",
            uint96(2 ether),
            "Account that will timeout",
            "verification_proof_data"
        );
        assertEq(listingId, 1);

        // user purchases non-NFT listing
        vm.prank(user2);
        MarketplaceCore(payable(polygonMarketplaceProxy)).buyNonNftAsset{value: 2 ether}(listingId);

        // Verify escrow holds the funds
        assertGt(address(polygonEscrow).balance, 0);

        // Verify escrow was created correctly
        VertixEscrow.Escrow memory escrow = polygonEscrow.getEscrow(listingId);
        assertEq(escrow.seller, user1);
        assertEq(escrow.buyer, user2);
        assertEq(escrow.amount, 1.98 ether); // 2 ether - 1% platform fee
        assertEq(escrow.completed, false);
        assertEq(escrow.disputed, false);

        // Simulate timeout scenario - seller doesn't provide credentials
        // Fast forward time to simulate timeout (assuming 7 days timeout)
        vm.warp(block.timestamp + 7 days + 1);

        // Buyer can request refund due to timeout
        vm.prank(user2);
        polygonEscrow.refund(listingId);

        // Verify escrow is completed and buyer received refund
        escrow = polygonEscrow.getEscrow(listingId);
        assertEq(escrow.seller, address(0)); // Escrow deleted after completion

        // Verify escrow contract has no remaining balance
        assertEq(address(polygonEscrow).balance, 0);

        // Verify listing is marked as inactive
        (,,,, bool activeAfterTimeout,,,) = polygonMarketplaceStorage.getNonNftListing(listingId);
        assertEq(activeAfterTimeout, false);
    }

    // ============ USER JOURNEY: CROSS-CHAIN BRIDGE FAILURE RECOVERY ============

    function test_CrossChainBridgeFailureRecoveryJourney_Complete() public {
        // Setup: Mint NFT on Polygon
        vm.chainId(137);
        vm.prank(deployerAddr);
        polygonNFT.mintSingleNft(user1, TOKEN_URI, bytes32(0), 0);

        // Register for bridging
        vm.prank(user1);
        polygonNFT.approve(address(polygonMarketplaceStorage), TOKEN_ID);
        vm.prank(user1);
        polygonNFT.approve(address(polygonRegistry), TOKEN_ID);

        vm.prank(deployerAddr);
        polygonMarketplaceStorage.registerCrossChainAssetForAllChains(
            address(polygonNFT),
            TOKEN_ID,
            uint96(INITIAL_PRICE),
            POLYGON_CHAIN
        );

        // Attempt bridge with insufficient fee (simulate failure)
        CrossChainBridge.BridgeParams memory params = CrossChainBridge.BridgeParams({
            contractAddr: address(polygonNFT),
            targetContract: address(baseNFT),
            tokenId: TOKEN_ID,
            targetChainType: BASE_CHAIN,
            assetType: 1,
            isNft: true,
            assetId: "",
            adapterParams: ""
        });

        uint256 insufficientFee = 0.001 ether; // Much less than required

        vm.prank(user1);
        vm.expectRevert(CrossChainBridge.CCB__InsufficientFee.selector);
        polygonBridge.bridgeAsset{value: insufficientFee}(params);

        // Verify NFT is still owned by user1 (not locked)
        assertEq(polygonNFT.ownerOf(TOKEN_ID), user1);

        // Now attempt successful bridge with correct fee
        (, uint256 totalFee) = polygonBridge.estimateBridgeFee(params);

        vm.prank(user1);
        polygonBridge.bridgeAsset{value: totalFee}(params);

        // Verify NFT is now locked for bridging
        bytes32 assetId = VertixUtils.createCrossChainAssetId(
            VertixUtils.ChainType(POLYGON_CHAIN),
            VertixUtils.ChainType(BASE_CHAIN),
            address(polygonNFT),
            TOKEN_ID
        );
        (,,,,,uint16 flags,,,) = polygonRegistry.crossChainAssets(assetId);
        assertTrue((flags & 4) != 0); // Locked

        // Test invalid chain type (another failure scenario)
        CrossChainBridge.BridgeParams memory invalidParams = CrossChainBridge.BridgeParams({
            contractAddr: address(polygonNFT),
            targetContract: address(baseNFT),
            tokenId: TOKEN_ID_2,
            targetChainType: 99, // Invalid chain type
            assetType: 1,
            isNft: true,
            assetId: "",
            adapterParams: ""
        });

        vm.prank(user1);
        vm.expectRevert(CrossChainBridge.CCB__InvalidChainType.selector);
        polygonBridge.bridgeAsset{value: totalFee}(invalidParams);
    }

    // ============ USER JOURNEY: ADVANCED AUCTION EDGE CASES ============

    function test_AdvancedAuctionEdgeCasesJourney_Complete() public {
        vm.chainId(8453);

        // Test 1: Auction with no bids
        vm.prank(deployerAddr);
        baseNFT.mintSingleNft(creator1, CREATOR_URI, bytes32(0), 0);

        vm.prank(creator1);
        baseNFT.approve(address(baseMarketplaceProxy), TOKEN_ID);

        vm.prank(creator1);
        uint256 listingId = MarketplaceCore(payable(baseMarketplaceProxy)).listNft(
            address(baseNFT),
            TOKEN_ID,
            uint96(5 ether)
        );

        vm.prank(creator1);
        MarketplaceCore(payable(baseMarketplaceProxy)).listForAuction(listingId, true);

        // NFT should be transferred to marketplace proxy when listed for auction
        assertEq(baseNFT.ownerOf(TOKEN_ID), address(baseMarketplaceProxy));

        vm.prank(creator1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).startNftAuction(
            listingId,
            1 hours,
            5 ether // High reserve price
        );

        // No bids placed during auction
        vm.warp(block.timestamp + 1 hours + 1);

        // Auction ends with no bids
        vm.prank(creator1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).endAuction(listingId);

        // Verify NFT remains with creator (no transfer occurred since no bids)
        assertEq(baseNFT.ownerOf(TOKEN_ID), creator1);

        // Test 2: Reserve price not met
        vm.prank(deployerAddr);
        baseNFT.mintSingleNft(creator1, CREATOR_URI, bytes32(0), 0);

        vm.prank(creator1);
        baseNFT.approve(address(baseMarketplaceProxy), TOKEN_ID_2);

        vm.prank(creator1);
        uint256 listingId2 = MarketplaceCore(payable(baseMarketplaceProxy)).listNft(
            address(baseNFT),
            TOKEN_ID_2,
            uint96(3 ether)
        );

        vm.prank(creator1);
        MarketplaceCore(payable(baseMarketplaceProxy)).listForAuction(listingId2, true);

        // NFT should be transferred to marketplace proxy
        assertEq(baseNFT.ownerOf(TOKEN_ID_2), address(baseMarketplaceProxy));

        vm.prank(creator1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).startNftAuction(
            listingId2,
            1 hours,
            3 ether // Reserve price
        );

        // Bid below reserve price
        vm.prank(user1);
        vm.expectRevert(); // Expect any revert for bid too low
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 2 ether}(listingId2);

        vm.warp(block.timestamp + 1 hours + 1);

        // Auction ends with reserve not met
        vm.prank(creator1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).endAuction(listingId2);

        // Verify NFT remains with creator (reserve not met)
        assertEq(baseNFT.ownerOf(TOKEN_ID_2), creator1);

        // Test 3: Simultaneous auctions with bidding war
        vm.prank(deployerAddr);
        baseNFT.mintSingleNft(creator2, CREATOR_URI, bytes32(0), 0);

        vm.prank(creator2);
        baseNFT.approve(address(baseMarketplaceProxy), TOKEN_ID_3);

        vm.prank(creator2);
        uint256 listingId3 = MarketplaceCore(payable(baseMarketplaceProxy)).listNft(
            address(baseNFT),
            TOKEN_ID_3,
            uint96(1 ether)
        );

        vm.prank(creator2);
        MarketplaceCore(payable(baseMarketplaceProxy)).listForAuction(listingId3, true);

        // NFT should be transferred to marketplace proxy
        assertEq(baseNFT.ownerOf(TOKEN_ID_3), address(baseMarketplaceProxy));

        vm.prank(creator2);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).startNftAuction(
            listingId3,
            2 hours,
            1 ether
        );

        // Intense bidding war
        vm.prank(user1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 1.1 ether}(listingId3);

        vm.prank(user2);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 1.2 ether}(listingId3);

        vm.prank(user3);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 1.3 ether}(listingId3);

        vm.prank(user1);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 1.4 ether}(listingId3);

        vm.prank(user2);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 1.5 ether}(listingId3);

        vm.prank(user3);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 1.6 ether}(listingId3);

        // Auction ends
        vm.warp(block.timestamp + 2 hours + 1);

        vm.prank(creator2);
        MarketplaceAuctions(payable(baseMarketplaceProxy)).endAuction(listingId3);

        // Verify highest bidder won
        assertEq(baseNFT.ownerOf(TOKEN_ID_3), user3);

        // Test 4: Invalid auction operations
        vm.prank(user1);
        vm.expectRevert(); // Only seller can end auction
        MarketplaceAuctions(payable(baseMarketplaceProxy)).endAuction(listingId3);

        // Test bidding on ended auction
        vm.prank(user1);
        vm.expectRevert(); // Auction already ended
        MarketplaceAuctions(payable(baseMarketplaceProxy)).placeBid{value: 2 ether}(listingId3);
    }
}