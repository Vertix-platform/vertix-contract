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
        // Attempt to delegatecall to MarketplaceCore
        (bool success, bytes memory returndata) = marketplaceCoreAddress.delegatecall(msg.data);

        // If core call failed, try MarketplaceAuctions
        if (!success) {
            (success, returndata) = marketplaceAuctionsAddress.delegatecall(msg.data);
        }

        // Revert with returndata if both delegatecalls failed
        if (!success) {
            assembly {
                revert(add(32, returndata), mload(returndata))
            }
        }

        // Return returndata on success
        assembly {
            return(add(32, returndata), mload(returndata))
        }
    }

    /**
     * @dev Allows the contract to receive plain Ether.
     * This is a best practice when a contract has a payable fallback function.
     */
    receive() external payable {}

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