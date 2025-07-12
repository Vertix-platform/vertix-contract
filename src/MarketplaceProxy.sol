// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title MarketplaceProxy
 * @dev Main entry point for the marketplace, utilizing delegatecall to
 * forward calls to the core and auction logic contracts.
 */
contract MarketplaceProxy {
    /*//////////////////////////////////////////////////////////////
    *                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public marketplaceCoreAddress;
    address public marketplaceAuctionsAddress;

    /*//////////////////////////////////////////////////////////////
    *                           CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _marketplaceCoreAddress, address _marketplaceAuctionsAddress) {
        require(_marketplaceCoreAddress != address(0), "MP__InvalidCoreAddress");
        require(_marketplaceAuctionsAddress != address(0), "MP__InvalidAuctionsAddress");

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
            selector == bytes4(keccak256("startNftAuction(address,uint256,uint96,uint256)")) ||
            selector == bytes4(keccak256("startNonNftAuction(uint8,string,uint96,string,uint256)")) ||
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
     * Only callable by the current MarketplaceCore contract (acting as owner via delegatecall).
     * @param _newMarketplaceCoreAddress The new address for MarketplaceCore.
     */
    function updateMarketplaceCoreAddress(address _newMarketplaceCoreAddress) external {
        // The actual access control logic (e.g., owner check) is handled by
        // the target implementation contract (MarketplaceCore) during the delegatecall.
        // This function merely provides an entry point for the delegatecall.
        (bool success, bytes memory returndata) = marketplaceCoreAddress.delegatecall(
            abi.encodeWithSelector(this.updateMarketplaceCoreAddress.selector, _newMarketplaceCoreAddress)
        );
        require(success, string(returndata));
    }

    /**
     * @dev Updates the address of the MarketplaceAuctions contract.
     * Only callable by the current MarketplaceCore contract (acting as owner via delegatecall).
     * @param _newMarketplaceAuctionsAddress The new address for MarketplaceAuctions.
     */
    function updateMarketplaceAuctionsAddress(address _newMarketplaceAuctionsAddress) external {
        // The actual access control logic is handled by the target implementation contract.
        (bool success, bytes memory returndata) = marketplaceCoreAddress.delegatecall(
            abi.encodeWithSelector(this.updateMarketplaceAuctionsAddress.selector, _newMarketplaceAuctionsAddress)
        );
        require(success, string(returndata));
    }
}