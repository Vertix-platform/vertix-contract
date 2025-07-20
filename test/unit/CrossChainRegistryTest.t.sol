// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CrossChainRegistry} from "../../src/CrossChainRegistry.sol";
import {MarketplaceStorage} from "../../src/MarketplaceStorage.sol";
import {VertixNFT} from "../../src/VertixNFT.sol";
import {DeployVertix} from "../../script/DeployVertix.s.sol";
import {VertixUtils} from "../../src/libraries/VertixUtils.sol";

contract CrossChainRegistryTest is Test {
    // DeployVertix script instance
    DeployVertix public deployer;

    // Contract addresses from deployment
    DeployVertix.VertixAddresses public vertixAddresses;

    // Contract instances
    CrossChainRegistry public registry;
    MarketplaceStorage public storageContract;
    VertixNFT public nftContract;

    // Test addresses
    address public owner;
    address public authorizedContract = makeAddr("authorizedContract");
    address public unauthorizedContract = makeAddr("unauthorizedContract");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public bridgeContract = makeAddr("bridgeContract");
    address public governanceContract = makeAddr("governanceContract");

    // Test constants
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant TOKEN_ID_2 = 2;
    uint8 public constant ORIGIN_CHAIN = 1;
    uint8 public constant TARGET_CHAIN = 2;
    uint8 public constant ASSET_TYPE = 1;
    uint96 public constant INITIAL_PRICE = 1 ether;
    uint96 public constant NEW_PRICE = 1.5 ether;
    uint96 public constant BRIDGE_FEE = 0.1 ether;
    uint32 public constant CONFIRMATION_BLOCKS = 12;
    uint16 public constant FEE_BPS = 50; // 0.5%
    string public constant ASSET_ID = "test-asset-123";
    string public constant METADATA = "test-metadata";
    bytes32 public constant VERIFICATION_HASH = keccak256("test-verification");

    // Test events
    event CrossChainAssetRegistered(
        bytes32 indexed assetId,
        uint8 indexed originChain,
        uint8 indexed targetChain,
        address originContract,
        uint256 tokenId
    );

    event CrossChainMessageQueued(
        bytes32 indexed messageHash,
        uint8 indexed sourceChain,
        uint8 indexed targetChain,
        uint8 messageType
    );

    event CrossChainSyncCompleted(
        bytes32 indexed assetId,
        uint8 indexed chainType,
        uint96 syncedPrice,
        uint64 blockNumber
    );

    event ChainConfigUpdated(
        uint8 indexed chainType,
        address bridgeContract,
        bool isActive
    );

    event BridgeRequestCreated(
        bytes32 indexed requestId,
        address indexed owner,
        uint16 indexed targetChainId,
        uint256 tokenId,
        uint96 fee
    );

    event AssetUnlocked(
        bytes32 indexed requestId,
        address indexed owner,
        address nftContract,
        uint256 tokenId
    );

    event NonNftAssetUnlocked(
        bytes32 indexed requestId,
        address indexed owner,
        uint8 assetType,
        string assetId
    );

    function setUp() public {
        // Create deployer instance
        deployer = new DeployVertix();

        // Deploy all contracts using the DeployVertix script
        vertixAddresses = deployer.deployVertix();

        // Get contract instances
        registry = CrossChainRegistry(vertixAddresses.crossChainRegistry);
        storageContract = MarketplaceStorage(vertixAddresses.marketplaceStorage);
        nftContract = VertixNFT(vertixAddresses.nft);

        // Get the owner from the registry contract
        owner = registry.owner();

        // Fund test accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(authorizedContract, 1 ether);
        vm.deal(unauthorizedContract, 1 ether);

        // Authorize the test contract
        vm.prank(owner);
        registry.authorizeContract(authorizedContract, true);
    }

    /*//////////////////////////////////////////////////////////////
                    HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Helper function to create a cross-chain asset ID
     */
    function _createAssetId(address contractAddr, uint256 tokenId) internal pure returns (bytes32) {
        return VertixUtils.createCrossChainAssetId(
            VertixUtils.ChainType(ORIGIN_CHAIN),
            VertixUtils.ChainType(TARGET_CHAIN),
            contractAddr,
            tokenId
        );
    }

    /**
     * @dev Helper function to create a non-NFT asset ID
     */
    function _createNonNftAssetId(address contractAddr, string memory assetId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(ORIGIN_CHAIN, contractAddr, assetId));
    }

    /**
     * @dev Helper function to create a bridge request ID
     */
    function _createBridgeRequestId(address sender, address contractAddr, uint256 tokenId, bool isNft) internal view returns (bytes32) {
        if (isNft) {
            return keccak256(abi.encodePacked(sender, contractAddr, tokenId, TARGET_CHAIN, block.timestamp));
        } else {
            return keccak256(abi.encodePacked(sender, contractAddr, ASSET_ID, TARGET_CHAIN, block.timestamp));
        }
    }

    /**
     * @dev Helper function to create a non-NFT listing for testing
     */
    function _createNonNftListing() internal returns (uint256 listingId) {
        vm.prank(owner);
        listingId = storageContract.createNonNftListing(
            user1,
            ASSET_TYPE,
            ASSET_ID,
            INITIAL_PRICE,
            METADATA,
            VERIFICATION_HASH
        );

        // Mark listing as active
        vm.prank(owner);
        storageContract.updateNonNftListingFlags(listingId, 1);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeploymentVerification() public view {
        // Verify that the registry contract was deployed correctly
        assertTrue(vertixAddresses.crossChainRegistry != address(0), "Registry should be deployed");
        assertTrue(address(registry) != address(0), "Registry instance should be valid");

        // Verify initial state
        assertEq(registry.owner(), owner, "Owner should be set correctly");
        assertEq(registry.marketplaceStorage(), address(storageContract), "Marketplace storage should be set");
        assertTrue(registry.authorizedContracts(owner), "Owner should be authorized");
        assertEq(registry.totalCrossChainAssets(), 0, "Initial asset count should be 0");
        assertEq(registry.totalBridgeRequests(), 0, "Initial bridge request count should be 0");
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizeContract() public {
        vm.prank(owner);
        registry.authorizeContract(authorizedContract, true);

        assertTrue(registry.authorizedContracts(authorizedContract), "Contract should be authorized");
    }

    function test_RevertIf_AuthorizeContract_NotOwner() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__NotOwner.selector);
        registry.authorizeContract(authorizedContract, true);
    }

    function test_DeauthorizeContract() public {
        // First authorize
        vm.prank(owner);
        registry.authorizeContract(authorizedContract, true);

        // Then deauthorize
        vm.prank(owner);
        registry.authorizeContract(authorizedContract, false);

        assertFalse(registry.authorizedContracts(authorizedContract), "Contract should be deauthorized");
    }

    /*//////////////////////////////////////////////////////////////
                    CHAIN CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetChainConfig() public {
        vm.prank(owner);
        registry.setChainConfig(
            ORIGIN_CHAIN,
            bridgeContract,
            governanceContract,
            CONFIRMATION_BLOCKS,
            FEE_BPS,
            true
        );

        CrossChainRegistry.ChainConfig memory config = registry.getChainConfig(ORIGIN_CHAIN);
        assertEq(config.bridgeContract, bridgeContract, "Bridge contract should be set");
        assertEq(config.governanceContract, governanceContract, "Governance contract should be set");
        assertEq(config.confirmationBlocks, CONFIRMATION_BLOCKS, "Confirmation blocks should be set");
        assertEq(config.feeBps, FEE_BPS, "Fee BPS should be set");
        assertTrue(config.isActive, "Chain should be active");
        assertGt(config.lastBlockSynced, 0, "Last block synced should be set");
    }

    function test_SetChainConfig_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ChainConfigUpdated(ORIGIN_CHAIN, bridgeContract, true);

        registry.setChainConfig(
            ORIGIN_CHAIN,
            bridgeContract,
            governanceContract,
            CONFIRMATION_BLOCKS,
            FEE_BPS,
            true
        );
    }

    function test_RevertIf_SetChainConfig_NotOwner() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__NotOwner.selector);
        registry.setChainConfig(
            ORIGIN_CHAIN,
            bridgeContract,
            governanceContract,
            CONFIRMATION_BLOCKS,
            FEE_BPS,
            true
        );
    }

    /*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN ASSET MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterCrossChainAsset() public {
        vm.prank(authorizedContract);
        bytes32 assetId = registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        // Verify asset registration
        (
            address originContract,
            address targetContract,
            uint256 tokenId,
            uint96 lastSyncPrice,
            uint64 lastSyncBlock,
            uint8 originChain,
            uint8 targetChain,
            bool isActive,
            bool isVerified,
            bool isLocked
        ) = registry.getCrossChainAsset(assetId);

        assertEq(originContract, address(nftContract), "Origin contract should be correct");
        assertEq(targetContract, address(0x123), "Target contract should be correct");
        assertEq(tokenId, TOKEN_ID, "Token ID should be correct");
        assertEq(lastSyncPrice, INITIAL_PRICE, "Initial price should be correct");
        assertEq(originChain, ORIGIN_CHAIN, "Origin chain should be correct");
        assertEq(targetChain, TARGET_CHAIN, "Target chain should be correct");
        assertTrue(isActive, "Asset should be active");
        assertFalse(isVerified, "Asset should not be verified initially");
        assertFalse(isLocked, "Asset should not be locked initially");
        assertGt(lastSyncBlock, 0, "Last sync block should be set");

        // Verify global state
        assertEq(registry.totalCrossChainAssets(), 1, "Total assets should be 1");
        assertEq(registry.chainAssetCounts(ORIGIN_CHAIN), 1, "Chain asset count should be 1");
        assertEq(registry.getAssetIdByContract(address(nftContract), TOKEN_ID), assetId, "Asset ID mapping should be correct");
    }

    function test_RegisterCrossChainAsset_EmitsEvent() public {
        vm.prank(authorizedContract);
        vm.expectEmit(true, true, true, true);
        emit CrossChainAssetRegistered(
            _createAssetId(address(nftContract), TOKEN_ID),
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(nftContract),
            TOKEN_ID
        );

        registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );
    }

    function test_RevertIf_RegisterCrossChainAsset_NotAuthorized() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__NotAuthorized.selector);
        registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );
    }

    function test_RevertIf_RegisterCrossChainAsset_AlreadyExists() public {
        // Register first time
        vm.prank(authorizedContract);
        registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        // Try to register again
        vm.prank(authorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__AssetAlreadyExists.selector);
        registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x456),
            INITIAL_PRICE
        );
    }

    function test_UpdateAssetSync() public {
        // First register asset
        vm.prank(authorizedContract);
        bytes32 assetId = registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        // Update sync
        vm.prank(authorizedContract);
        registry.updateAssetSync(assetId, NEW_PRICE, TARGET_CHAIN);

        // Verify update
        (
            ,,,
            uint96 lastSyncPrice,
            uint64 lastSyncBlock,
            ,,
            ,,
        ) = registry.getCrossChainAsset(assetId);

        assertEq(lastSyncPrice, NEW_PRICE, "Price should be updated");
        assertGt(lastSyncBlock, 0, "Sync block should be updated");
    }

    function test_UpdateAssetSync_EmitsEvent() public {
        // First register asset
        vm.prank(authorizedContract);
        bytes32 assetId = registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        // Update sync
        vm.prank(authorizedContract);
        vm.expectEmit(true, true, false, true);
        emit CrossChainSyncCompleted(assetId, TARGET_CHAIN, NEW_PRICE, uint64(block.number));

        registry.updateAssetSync(assetId, NEW_PRICE, TARGET_CHAIN);
    }

    function test_RevertIf_UpdateAssetSync_NotAuthorized() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__NotAuthorized.selector);
        registry.updateAssetSync(bytes32(0), NEW_PRICE, TARGET_CHAIN);
    }

    function test_RevertIf_UpdateAssetSync_AssetNotExists() public {
        vm.prank(authorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__AssetNotExists.selector);
        registry.updateAssetSync(bytes32(0), NEW_PRICE, TARGET_CHAIN);
    }

    /*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN MESSAGE QUEUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_QueueCrossChainMessage() public {
        bytes memory payload = abi.encode("test", "data");

        vm.prank(authorizedContract);
        bytes32 messageHash = registry.queueCrossChainMessage(
            1, // messageType
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            payload
        );

        // Verify message queue
        bytes32[] memory queue = registry.getChainMessageQueue(TARGET_CHAIN);
        assertEq(queue.length, 1, "Queue should have 1 message");
        assertEq(queue[0], messageHash, "Message hash should be correct");
        assertEq(registry.getPendingMessageCount(TARGET_CHAIN), 1, "Pending count should be 1");
    }

    function test_QueueCrossChainMessage_EmitsEvent() public {
        bytes memory payload = abi.encode("test", "data");

        vm.prank(authorizedContract);
        vm.expectEmit(false, true, true, true);
        emit CrossChainMessageQueued(bytes32(0), ORIGIN_CHAIN, TARGET_CHAIN, 1);

        registry.queueCrossChainMessage(1, ORIGIN_CHAIN, TARGET_CHAIN, payload);
    }

    function test_RevertIf_QueueCrossChainMessage_NotAuthorized() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__NotAuthorized.selector);
        registry.queueCrossChainMessage(1, ORIGIN_CHAIN, TARGET_CHAIN, "");
    }

    function test_MarkMessageProcessed() public {
        // First queue a message
        vm.prank(authorizedContract);
        bytes32 messageHash = registry.queueCrossChainMessage(1, ORIGIN_CHAIN, TARGET_CHAIN, "");

        // Mark as processed
        vm.prank(authorizedContract);
        registry.markMessageProcessed(messageHash);

        // Verify pending count is 0
        assertEq(registry.getPendingMessageCount(TARGET_CHAIN), 0, "Pending count should be 0");
    }

    function test_RevertIf_MarkMessageProcessed_NotAuthorized() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__NotAuthorized.selector);
        registry.markMessageProcessed(bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                    BRIDGE REQUEST MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterBridgeRequest_NFT() public {
        // Set up chain config first
        vm.prank(owner);
        registry.setChainConfig(
            TARGET_CHAIN,
            bridgeContract,
            governanceContract,
            CONFIRMATION_BLOCKS,
            FEE_BPS,
            true
        );

        vm.prank(authorizedContract);
        bytes32 requestId = registry.registerBridgeRequest(
            user1,
            address(nftContract),
            TOKEN_ID,
            TARGET_CHAIN,
            address(0x123),
            BRIDGE_FEE,
            true, // isNft
            0, // assetType
            "" // assetId
        );

        // Verify bridge request
        CrossChainRegistry.BridgeRequest memory request = registry.getBridgeRequest(requestId);
        assertEq(request.owner, user1, "Owner should be correct");
        assertEq(request.nftContract, address(nftContract), "NFT contract should be correct");
        assertEq(request.tokenId, TOKEN_ID, "Token ID should be correct");
        assertEq(request.fee, BRIDGE_FEE, "Fee should be correct");
        assertEq(request.targetChainType, TARGET_CHAIN, "Target chain should be correct");
        assertTrue(request.isNft, "Should be NFT");
        assertEq(request.status, 0, "Status should be 0");

        // Verify global state
        assertEq(registry.totalBridgeRequests(), 1, "Total requests should be 1");

        // Verify user requests
        bytes32[] memory userRequests = registry.getUserBridgeRequests(user1);
        assertEq(userRequests.length, 1, "User should have 1 request");
        assertEq(userRequests[0], requestId, "Request ID should be correct");
    }

    function test_RegisterBridgeRequest_NonNFT() public {
        // Set up chain config first
        vm.prank(owner);
        registry.setChainConfig(
            TARGET_CHAIN,
            bridgeContract,
            governanceContract,
            CONFIRMATION_BLOCKS,
            FEE_BPS,
            true
        );

        vm.prank(authorizedContract);
        bytes32 requestId = registry.registerBridgeRequest(
            user1,
            address(0x456),
            0, // tokenId (not used for non-NFT)
            TARGET_CHAIN,
            address(0x123),
            BRIDGE_FEE,
            false, // isNft
            ASSET_TYPE,
            ASSET_ID
        );

        // Verify bridge request
        CrossChainRegistry.BridgeRequest memory request = registry.getBridgeRequest(requestId);
        assertEq(request.owner, user1, "Owner should be correct");
        assertEq(request.assetType, ASSET_TYPE, "Asset type should be correct");
        assertEq(request.assetId, ASSET_ID, "Asset ID should be correct");
        assertFalse(request.isNft, "Should not be NFT");
    }

    function test_RegisterBridgeRequest_EmitsEvent() public {
        // Set up chain config first
        vm.prank(owner);
        registry.setChainConfig(
            TARGET_CHAIN,
            bridgeContract,
            governanceContract,
            CONFIRMATION_BLOCKS,
            FEE_BPS,
            true
        );

        vm.prank(authorizedContract);
        vm.expectEmit(false, true, true, true);
        emit BridgeRequestCreated(bytes32(0), user1, FEE_BPS, TOKEN_ID, BRIDGE_FEE);

        registry.registerBridgeRequest(
            user1,
            address(nftContract),
            TOKEN_ID,
            TARGET_CHAIN,
            address(0x123),
            BRIDGE_FEE,
            true,
            0,
            ""
        );
    }

    function test_RevertIf_RegisterBridgeRequest_NotAuthorized() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__NotAuthorized.selector);
        registry.registerBridgeRequest(
            user1,
            address(nftContract),
            TOKEN_ID,
            TARGET_CHAIN,
            address(0x123),
            BRIDGE_FEE,
            true,
            0,
            ""
        );
    }

    function test_LockAsset_NFT() public {
        // First register asset
        vm.prank(authorizedContract);
        bytes32 assetId = registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        // Mint NFT to user1
        vm.prank(owner);
        nftContract.mintSingleNft(user1, "test-uri", bytes32(0), 0);

        // Approve registry to transfer NFT
        vm.prank(user1);
        nftContract.approve(address(registry), TOKEN_ID);

        // Lock asset
        vm.prank(authorizedContract);
        registry.lockAsset(
            user1,
            address(nftContract),
            TOKEN_ID,
            true, // isNft
            "",
            ORIGIN_CHAIN
        );

        // Verify asset is locked
        (
            ,,,,,
            ,,
            bool isActive,
            ,
            bool isLocked
        ) = registry.getCrossChainAsset(assetId);

        assertTrue(isActive, "Asset should still be active");
        assertTrue(isLocked, "Asset should be locked");
    }

    

    function test_RevertIf_LockAsset_NotAuthorized() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__NotAuthorized.selector);
        registry.lockAsset(
            user1,
            address(nftContract),
            TOKEN_ID,
            true,
            "",
            ORIGIN_CHAIN
        );
    }

    function test_RevertIf_LockAsset_AssetNotExists() public {
        vm.prank(authorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__AssetNotExists.selector);
        registry.lockAsset(
            user1,
            address(nftContract),
            TOKEN_ID,
            true,
            "",
            ORIGIN_CHAIN
        );
    }

    function test_RevertIf_LockAsset_UnauthorizedTransfer() public {
        // First register asset
        vm.prank(authorizedContract);
        registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        // Mint NFT to user1 (not user2)
        vm.prank(owner);
        nftContract.mintSingleNft(user1, "test-uri", bytes32(0), 0);

        // Try to lock with wrong owner
        vm.prank(authorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__UnauthorizedTransfer.selector);
        registry.lockAsset(
            user2, // wrong owner
            address(nftContract),
            TOKEN_ID,
            true,
            "",
            ORIGIN_CHAIN
        );
    }

    function test_UnlockAsset_NFT() public {
        // First register and lock asset
        vm.prank(authorizedContract);
        bytes32 assetId = registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        // Mint NFT to user1
        vm.prank(owner);
        nftContract.mintSingleNft(user1, "test-uri", bytes32(0), 0);

        // Approve registry to transfer NFT
        vm.prank(user1);
        nftContract.approve(address(registry), TOKEN_ID);

        // Lock asset
        vm.prank(authorizedContract);
        registry.lockAsset(
            user1,
            address(nftContract),
            TOKEN_ID,
            true,
            "",
            ORIGIN_CHAIN
        );

        // Unlock asset
        bytes32 requestId = _createBridgeRequestId(user1, address(nftContract), TOKEN_ID, true);
        vm.prank(authorizedContract);
        registry.unlockAsset(
            requestId,
            user1,
            address(nftContract),
            TOKEN_ID,
            true,
            0,
            "",
            ORIGIN_CHAIN
        );

        // Verify asset is unlocked
        (
            ,,,,,
            ,,
            bool isActive,
            ,
            bool isLocked
        ) = registry.getCrossChainAsset(assetId);

        assertTrue(isActive, "Asset should still be active");
        assertFalse(isLocked, "Asset should be unlocked");
    }



    function test_UnlockAsset_EmitsEvent() public {
        // First register and lock asset
        vm.prank(authorizedContract);
        registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        // Mint NFT to user1
        vm.prank(owner);
        nftContract.mintSingleNft(user1, "test-uri", bytes32(0), 0);

        // Approve registry to transfer NFT
        vm.prank(user1);
        nftContract.approve(address(registry), TOKEN_ID);

        // Lock asset
        vm.prank(authorizedContract);
        registry.lockAsset(
            user1,
            address(nftContract),
            TOKEN_ID,
            true,
            "",
            ORIGIN_CHAIN
        );

        // Unlock asset
        bytes32 requestId = _createBridgeRequestId(user1, address(nftContract), TOKEN_ID, true);
        vm.prank(authorizedContract);
        vm.expectEmit(true, true, false, true);
        emit AssetUnlocked(requestId, user1, address(nftContract), TOKEN_ID);

        registry.unlockAsset(
            requestId,
            user1,
            address(nftContract),
            TOKEN_ID,
            true,
            0,
            "",
            ORIGIN_CHAIN
        );
    }



    function test_RevertIf_UnlockAsset_NotAuthorized() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__NotAuthorized.selector);
        registry.unlockAsset(
            bytes32(0),
            user1,
            address(nftContract),
            TOKEN_ID,
            true,
            0,
            "",
            ORIGIN_CHAIN
        );
    }

    function test_RevertIf_UnlockAsset_AssetNotExists() public {
        vm.prank(authorizedContract);
        vm.expectRevert(CrossChainRegistry.CCR__AssetNotExists.selector);
        registry.unlockAsset(
            bytes32(0),
            user1,
            address(nftContract),
            TOKEN_ID,
            true,
            0,
            "",
            ORIGIN_CHAIN
        );
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCrossChainAsset() public {
        // First register asset
        vm.prank(authorizedContract);
        bytes32 assetId = registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        // Get asset details
        (
            address originContract,
            address targetContract,
            uint256 tokenId,
            uint96 lastSyncPrice,
            uint64 lastSyncBlock,
            uint8 originChain,
            uint8 targetChain,
            bool isActive,
            bool isVerified,
            bool isLocked
        ) = registry.getCrossChainAsset(assetId);

        assertEq(originContract, address(nftContract), "Origin contract should be correct");
        assertEq(targetContract, address(0x123), "Target contract should be correct");
        assertEq(tokenId, TOKEN_ID, "Token ID should be correct");
        assertEq(lastSyncPrice, INITIAL_PRICE, "Price should be correct");
        assertEq(originChain, ORIGIN_CHAIN, "Origin chain should be correct");
        assertEq(targetChain, TARGET_CHAIN, "Target chain should be correct");
        assertTrue(isActive, "Should be active");
        assertFalse(isVerified, "Should not be verified");
        assertFalse(isLocked, "Should not be locked");
        assertGt(lastSyncBlock, 0, "Sync block should be set");
    }

    function test_GetChainMessageQueue() public {
        // Queue a message
        vm.prank(authorizedContract);
        bytes32 messageHash = registry.queueCrossChainMessage(1, ORIGIN_CHAIN, TARGET_CHAIN, "");

        // Get queue
        bytes32[] memory queue = registry.getChainMessageQueue(TARGET_CHAIN);
        assertEq(queue.length, 1, "Queue should have 1 message");
        assertEq(queue[0], messageHash, "Message hash should be correct");
    }

        function test_GetPendingMessageCount() public {
        // Queue a message
        vm.prank(authorizedContract);
        bytes32 messageHash1 = registry.queueCrossChainMessage(1, ORIGIN_CHAIN, TARGET_CHAIN, "");

        // Check pending count
        assertEq(registry.getPendingMessageCount(TARGET_CHAIN), 1, "Should have 1 pending message");

        // Fast forward time to get different timestamp
        vm.warp(block.timestamp + 1);

        // Queue another message
        vm.prank(authorizedContract);
        registry.queueCrossChainMessage(1, ORIGIN_CHAIN, TARGET_CHAIN, "");

        // Check pending count
        assertEq(registry.getPendingMessageCount(TARGET_CHAIN), 2, "Should have 2 pending messages");

        // Mark first message as processed
        vm.prank(authorizedContract);
        registry.markMessageProcessed(messageHash1);

        // Check pending count again
        assertEq(registry.getPendingMessageCount(TARGET_CHAIN), 1, "Should have 1 pending message after processing one");
    }

    function test_GetAssetIdByContract() public {
        // First register asset
        vm.prank(authorizedContract);
        bytes32 assetId = registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        // Get asset ID by contract
        bytes32 retrievedAssetId = registry.getAssetIdByContract(address(nftContract), TOKEN_ID);
        assertEq(retrievedAssetId, assetId, "Asset ID should match");
    }

    function test_GetChainConfig() public {
        // Set chain config
        vm.prank(owner);
        registry.setChainConfig(
            ORIGIN_CHAIN,
            bridgeContract,
            governanceContract,
            CONFIRMATION_BLOCKS,
            FEE_BPS,
            true
        );

        // Get chain config
        CrossChainRegistry.ChainConfig memory config = registry.getChainConfig(ORIGIN_CHAIN);
        assertEq(config.bridgeContract, bridgeContract, "Bridge contract should be correct");
        assertEq(config.governanceContract, governanceContract, "Governance contract should be correct");
        assertEq(config.confirmationBlocks, CONFIRMATION_BLOCKS, "Confirmation blocks should be correct");
        assertEq(config.feeBps, FEE_BPS, "Fee BPS should be correct");
        assertTrue(config.isActive, "Should be active");
        assertGt(config.lastBlockSynced, 0, "Last block synced should be set");
    }

    function test_GetBridgeRequest() public {
        // Set up chain config first
        vm.prank(owner);
        registry.setChainConfig(
            TARGET_CHAIN,
            bridgeContract,
            governanceContract,
            CONFIRMATION_BLOCKS,
            FEE_BPS,
            true
        );

        // Register bridge request
        vm.prank(authorizedContract);
        bytes32 requestId = registry.registerBridgeRequest(
            user1,
            address(nftContract),
            TOKEN_ID,
            TARGET_CHAIN,
            address(0x123),
            BRIDGE_FEE,
            true,
            0,
            ""
        );

        // Get bridge request
        CrossChainRegistry.BridgeRequest memory request = registry.getBridgeRequest(requestId);
        assertEq(request.owner, user1, "Owner should be correct");
        assertEq(request.nftContract, address(nftContract), "NFT contract should be correct");
        assertEq(request.tokenId, TOKEN_ID, "Token ID should be correct");
        assertEq(request.fee, BRIDGE_FEE, "Fee should be correct");
        assertEq(request.targetChainType, TARGET_CHAIN, "Target chain should be correct");
        assertTrue(request.isNft, "Should be NFT");
        assertEq(request.status, 0, "Status should be 0");
    }

    function test_GetUserBridgeRequests() public {
        // Set up chain config first
        vm.prank(owner);
        registry.setChainConfig(
            TARGET_CHAIN,
            bridgeContract,
            governanceContract,
            CONFIRMATION_BLOCKS,
            FEE_BPS,
            true
        );

        // Register bridge requests
        vm.prank(authorizedContract);
        registry.registerBridgeRequest(
            user1,
            address(nftContract),
            TOKEN_ID,
            TARGET_CHAIN,
            address(0x123),
            BRIDGE_FEE,
            true,
            0,
            ""
        );

        vm.prank(authorizedContract);
        registry.registerBridgeRequest(
            user1,
            address(nftContract),
            TOKEN_ID_2,
            TARGET_CHAIN,
            address(0x123),
            BRIDGE_FEE,
            true,
            0,
            ""
        );

        // Get user bridge requests
        bytes32[] memory userRequests = registry.getUserBridgeRequests(user1);
        assertEq(userRequests.length, 2, "User should have 2 requests");
    }

    /*//////////////////////////////////////////////////////////////
                    EDGE CASES AND INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleAssetsSameContract() public {
        // Register multiple assets from same contract
        vm.prank(authorizedContract);
        bytes32 assetId1 = registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        vm.prank(authorizedContract);
        bytes32 assetId2 = registry.registerCrossChainAsset(
            address(nftContract),
            TOKEN_ID_2,
            ORIGIN_CHAIN,
            TARGET_CHAIN,
            address(0x123),
            INITIAL_PRICE
        );

        assertEq(registry.totalCrossChainAssets(), 2, "Should have 2 assets");
        assertEq(registry.chainAssetCounts(ORIGIN_CHAIN), 2, "Chain should have 2 assets");
        assertEq(registry.getAssetIdByContract(address(nftContract), TOKEN_ID), assetId1, "Asset ID 1 should be correct");
        assertEq(registry.getAssetIdByContract(address(nftContract), TOKEN_ID_2), assetId2, "Asset ID 2 should be correct");
    }

    function test_MultipleChainConfigs() public {
        // Set multiple chain configs
        vm.prank(owner);
        registry.setChainConfig(1, address(0x111), address(0x222), 10, 25, true);

        vm.prank(owner);
        registry.setChainConfig(2, address(0x333), address(0x444), 20, 50, false);

        // Verify configs
        CrossChainRegistry.ChainConfig memory config1 = registry.getChainConfig(1);
        CrossChainRegistry.ChainConfig memory config2 = registry.getChainConfig(2);

        assertEq(config1.bridgeContract, address(0x111), "Chain 1 bridge should be correct");
        assertEq(config2.bridgeContract, address(0x333), "Chain 2 bridge should be correct");
        assertTrue(config1.isActive, "Chain 1 should be active");
        assertFalse(config2.isActive, "Chain 2 should not be active");
    }

    function test_MessageQueueMultipleChains() public {
        // Queue messages to different chains
        vm.prank(authorizedContract);
        registry.queueCrossChainMessage(1, ORIGIN_CHAIN, 1, "");

        vm.prank(authorizedContract);
        registry.queueCrossChainMessage(2, ORIGIN_CHAIN, 2, "");

        vm.prank(authorizedContract);
        registry.queueCrossChainMessage(3, ORIGIN_CHAIN, 1, "");

        // Verify queues
        assertEq(registry.getChainMessageQueue(1).length, 2, "Chain 1 should have 2 messages");
        assertEq(registry.getChainMessageQueue(2).length, 1, "Chain 2 should have 1 message");
        assertEq(registry.getPendingMessageCount(1), 2, "Chain 1 should have 2 pending messages");
        assertEq(registry.getPendingMessageCount(2), 1, "Chain 2 should have 1 pending message");
    }

    function test_BridgeRequestMultipleUsers() public {
        // Set up chain config first
        vm.prank(owner);
        registry.setChainConfig(
            TARGET_CHAIN,
            bridgeContract,
            governanceContract,
            CONFIRMATION_BLOCKS,
            FEE_BPS,
            true
        );

        // Register bridge requests for different users
        vm.prank(authorizedContract);
        registry.registerBridgeRequest(
            user1,
            address(nftContract),
            TOKEN_ID,
            TARGET_CHAIN,
            address(0x123),
            BRIDGE_FEE,
            true,
            0,
            ""
        );

        vm.prank(authorizedContract);
        registry.registerBridgeRequest(
            user2,
            address(nftContract),
            TOKEN_ID_2,
            TARGET_CHAIN,
            address(0x123),
            BRIDGE_FEE,
            true,
            0,
            ""
        );

        // Verify requests
        assertEq(registry.totalBridgeRequests(), 2, "Should have 2 total requests");
        assertEq(registry.getUserBridgeRequests(user1).length, 1, "User1 should have 1 request");
        assertEq(registry.getUserBridgeRequests(user2).length, 1, "User2 should have 1 request");
    }
}