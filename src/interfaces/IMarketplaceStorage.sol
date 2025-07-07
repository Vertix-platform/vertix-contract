// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IMarketplaceStorage
 * @dev Interface for MarketplaceStorage contract with custom errors
 */
interface IMarketplaceStorage {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error MarketplaceStorage__ListingNotActive();
    error MarketplaceStorage__NotSeller();
    error MarketplaceStorage__AlreadyListedForAuction();
    error MarketplaceStorage__InsufficientPrice();
    error MarketplaceStorage__ArrayLengthMismatch();
    error MarketplaceStorage__NotAuthorized();
    error MarketplaceStorage__NotOwner();
} 