// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MarketplaceStorage} from "./MarketplaceStorage.sol";

/**
 * @title MarketplaceProxy
 * @dev Main entry point for the marketplace, utilizing delegatecall to
 * forward calls to the core and auction logic contracts.
 */
contract MarketplaceProxy {
    error MP__InvalidCoreAddress();
    error MP__InvalidAuctionsAddress();
    error MP__FailedToGetStorageContract();
    error MP__FailedToGetOwner();
    error MP__NotAuthorized();

    /*//////////////////////////////////////////////////////////////
    *                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public marketplaceCoreAddress;
    address public marketplaceAuctionsAddress;

    /*//////////////////////////////////////////////////////////////
    *                           CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _marketplaceCoreAddress, address _marketplaceAuctionsAddress) {
        if (_marketplaceCoreAddress == address(0)) revert MP__InvalidCoreAddress();
        if (_marketplaceAuctionsAddress == address(0)) revert MP__InvalidAuctionsAddress();

        marketplaceCoreAddress = _marketplaceCoreAddress;
        marketplaceAuctionsAddress = _marketplaceAuctionsAddress;
    }

    /*//////////////////////////////////////////////////////////////
    *                       FALLBACK FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Fallback function to handle all incoming calls.
     * It attempts to delegatecall to MarketplaceCore first,
     * and if that fails, it tries MarketplaceAuctions.
     * This allows for a single entry point for all marketplace operations.
     */
    fallback() external payable {
        // Get function selector from calldata
        bytes4 selector;
        assembly {
            selector := calldataload(0)
        }

        // Check if this is an auction-related function using dynamic selector calculation
        bool isAuctionFunction = _isAuctionFunction(selector);

        if (isAuctionFunction) {
            // For auction functions, try MarketplaceAuctions first
            (bool success, bytes memory returndata) = marketplaceAuctionsAddress.delegatecall(msg.data);
            if (success) {
                assembly {
                    return(add(32, returndata), mload(returndata))
                }
            }
            // If auction function fails, revert with the error
            assembly {
                revert(add(32, returndata), mload(returndata))
            }
        } else {
            // For non-auction functions, try MarketplaceCore first
            (bool success, bytes memory returndata) = marketplaceCoreAddress.delegatecall(msg.data);
            if (success) {
                assembly {
                    return(add(32, returndata), mload(returndata))
                }
            }
            // If core function fails, revert with the error (don't try auctions)
            assembly {
                revert(add(32, returndata), mload(returndata))
            }
        }
    }

    /**
     * @dev Allows the contract to receive plain Ether.
     * This is a best practice when a contract has a payable fallback function.
     */
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
    *                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Dynamically checks if a function selector belongs to an auction function
     * @param selector The function selector to check
     * @return True if the function is auction-related
     */
    function _isAuctionFunction(bytes4 selector) internal pure returns (bool) {
        return
            selector == bytes4(keccak256("startNftAuction(uint256,uint24,uint96)")) ||
            selector == bytes4(keccak256("startNonNftAuction(uint256,uint24,uint96)")) ||
            selector == bytes4(keccak256("placeBid(uint256)")) ||
            selector == bytes4(keccak256("endAuction(uint256)")) ||
            selector == bytes4(keccak256("getAuctionInfo(uint256)")) ||
            selector == bytes4(keccak256("isAuctionExpired(uint256)")) ||
            selector == bytes4(keccak256("getTimeRemaining(uint256)"));
    }

    /*//////////////////////////////////////////////////////////////
    *                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Updates the address of the MarketplaceCore contract.
     * Only callable by the owner of the MarketplaceStorage contract.
     * @param _newMarketplaceCoreAddress The new address for MarketplaceCore.
     */
    function updateMarketplaceCoreAddress(address _newMarketplaceCoreAddress) external {
        if (_newMarketplaceCoreAddress == address(0)) revert MP__InvalidCoreAddress();


        // Check if caller is the owner of the storage contract
        // We need to get the storage contract address from the core contract
        (bool success, bytes memory returndata) = marketplaceCoreAddress.staticcall(
            abi.encodeWithSignature("STORAGE_CONTRACT()")
        );
        if(!success) revert MP__FailedToGetStorageContract();
        address storageContract = abi.decode(returndata, (address));

        // Check ownership
        (success, returndata) = storageContract.staticcall(
            abi.encodeWithSignature("owner()")
        );
        if(!success) revert MP__FailedToGetOwner();
        address owner = abi.decode(returndata, (address));
        if(msg.sender != owner) revert MP__NotAuthorized();

        // Update the proxys state variable
        marketplaceCoreAddress = _newMarketplaceCoreAddress;
    }

    /**
     * @dev Updates the address of the MarketplaceAuctions contract.
     * Only callable by the owner of the MarketplaceStorage contract.
     * @param _newMarketplaceAuctionsAddress The new address for MarketplaceAuctions.
     */
    function updateMarketplaceAuctionsAddress(address _newMarketplaceAuctionsAddress) external {
        if (_newMarketplaceAuctionsAddress == address(0)) revert MP__InvalidAuctionsAddress();

        // Check if caller is the owner of the storage contract
        // We need to get the storage contract address from the core contract
        (bool success, bytes memory returndata) = marketplaceCoreAddress.staticcall(
            abi.encodeWithSignature("STORAGE_CONTRACT()")
        );
        if(!success) revert MP__FailedToGetStorageContract();
        address storageContract = abi.decode(returndata, (address));

        // Check ownership
        (success, returndata) = storageContract.staticcall(
            abi.encodeWithSignature("owner()")
        );
        if(!success) revert MP__FailedToGetOwner();
        address owner = abi.decode(returndata, (address));
        if(msg.sender != owner) revert MP__NotAuthorized();

        // Update the proxys state variable
        marketplaceAuctionsAddress = _newMarketplaceAuctionsAddress;
    }
}