// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IVertixGovernance} from "./interfaces/IVertixGovernance.sol";
import {IVertixEscrow} from "./interfaces/IVertixEscrow.sol";

/**
 * @title MarketplaceFees
 * @dev Handles all fee calculations and distributions for the marketplace
 */
contract MarketplaceFees {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error MarketplaceFees__TransferFailed();
    error MarketplaceFees__InsufficientPayment();
    error MarketplaceFees__InvalidFeeConfig();

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Represents the distribution of fees for a sale
     */

    struct FeeDistribution {
        uint256 platformFee;
        uint256 royaltyAmount;
        uint256 sellerAmount;
        address platformRecipient;
        address royaltyRecipient;
    }
    /**
     * @dev Configuration for payment processing
     */
    struct PaymentConfig {
        uint256 totalPayment;
        uint256 salePrice;
        address nftContract;
        uint256 tokenId;
        address seller;
        bool hasRoyalties;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IVertixGovernance public immutable governanceContract;
    IVertixEscrow public immutable escrowContract;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeesDistributed(
        uint256 indexed salePrice,
        uint256 platformFee,
        uint256 royaltyAmount,
        address platformRecipient,
        address royaltyRecipient,
        address seller
    );

    event EscrowDeposit(
        uint256 indexed listingId,
        uint256 amount,
        address seller,
        address buyer
    );

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _governanceContract, address _escrowContract) {
        governanceContract = IVertixGovernance(_governanceContract);
        escrowContract = IVertixEscrow(_escrowContract);
    }

    /*//////////////////////////////////////////////////////////////
                          FEE CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Calculate fees for NFT sale with royalties
     * @param salePrice The total sale price of the NFT
     * @param nftContract The address of the NFT contract
     * @param tokenId The ID of the NFT being sold
     * @return FeeDistribution containing platform fee, royalty amount, seller amount, and recipients
     */
    function calculateNFTFees(
        uint256 salePrice,
        address nftContract,
        uint256 tokenId
    ) external view returns (FeeDistribution memory) {
        (uint256 platformFeeBps, address platformRecipient) = governanceContract.getFeeConfig();

        // Get royalty info
        (address royaltyRecipient, uint256 royaltyAmount) =
            IERC2981(nftContract).royaltyInfo(tokenId, salePrice);

        uint256 platformFee = (salePrice * platformFeeBps) / 10000;

        // Validate total deductions don't exceed sale price
        uint256 totalDeductions = platformFee + royaltyAmount;
        if (totalDeductions > salePrice) {
            revert MarketplaceFees__InvalidFeeConfig();
        }

        return FeeDistribution({
            platformFee: platformFee,
            royaltyAmount: royaltyAmount,
            sellerAmount: salePrice - totalDeductions,
            platformRecipient: platformRecipient,
            royaltyRecipient: royaltyRecipient
        });
    }

    /**
     * @dev Calculate fees for non-NFT sale (no royalties)
     * @param salePrice The total sale price of the item
     * @return FeeDistribution containing platform fee, royalty amount (0), seller amount, and recipients
     */
    function calculateNonNFTFees(uint256 salePrice) external view returns (FeeDistribution memory) {
        (uint256 platformFeeBps, address platformRecipient) = governanceContract.getFeeConfig();

        uint256 platformFee = (salePrice * platformFeeBps) / 10000;

        if (platformFee > salePrice) {
            revert MarketplaceFees__InvalidFeeConfig();
        }

        return FeeDistribution({
            platformFee: platformFee,
            royaltyAmount: 0,
            sellerAmount: salePrice - platformFee,
            platformRecipient: platformRecipient,
            royaltyRecipient: address(0)
        });
    }

    /**
     * @dev Calculate minimum bid amount for auction including fees
     * @param startingPrice The starting price of the NFT
     * @param currentHighestBid The current highest bid in the auction
     * @notice Ensures the bid covers platform fees and is higher than the current highest bid
     */
    function calculateMinimumBid(
        uint256 startingPrice,
        uint256 currentHighestBid
    ) external view returns (uint256 minimumBid) {
        (uint256 platformFeeBps,) = governanceContract.getFeeConfig();
        uint256 platformFee = (startingPrice * platformFeeBps) / 10000;

        minimumBid = currentHighestBid > 0 ? currentHighestBid + 1 : startingPrice;

        // Ensure bid covers minimum platform fee
        if (minimumBid < platformFee) {
            minimumBid = platformFee;
        }
    }

    /*//////////////////////////////////////////////////////////////
                         PAYMENT PROCESSING
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Process NFT sale payment with fee distribution
     * @param config Payment configuration containing sale details
     * @return refundAmount Amount to refund to buyer if overpaid
     * @notice This function handles the payment for NFT sales, distributing fees to platform, royalty recipient, and seller.
     */
    function processNFTSalePayment(
        PaymentConfig calldata config
    ) external payable returns (uint256 refundAmount) {
        if (msg.value < config.salePrice) {
            revert MarketplaceFees__InsufficientPayment();
        }

        FeeDistribution memory fees = this.calculateNFTFees(
            config.salePrice,
            config.nftContract,
            config.tokenId
        );

        // Distribute payments
        if (fees.platformFee > 0) {
            _safeTransferETH(fees.platformRecipient, fees.platformFee);
        }

        if (fees.royaltyAmount > 0) {
            _safeTransferETH(fees.royaltyRecipient, fees.royaltyAmount);
        }

        if (fees.sellerAmount > 0) {
            _safeTransferETH(config.seller, fees.sellerAmount);
        }

        // Calculate refund
        refundAmount = msg.value - config.salePrice;

        emit FeesDistributed(
            config.salePrice,
            fees.platformFee,
            fees.royaltyAmount,
            fees.platformRecipient,
            fees.royaltyRecipient,
            config.seller
        );
    }

    /**
     * @dev Process non-NFT sale payment with escrow
     * @param listingId The ID of the listing being purchased
     * @param salePrice The total sale price of the item
     * @param seller The address of the seller
     * @param buyer The address of the buyer
     * @return refundAmount Amount to refund to buyer if overpaid
     * @notice This function handles the payment for non-NFT sales, distributing platform fees and locking funds in escrow.
     */
    function processNonNFTSalePayment(
        uint256 listingId,
        uint256 salePrice,
        address seller,
        address buyer
    ) external payable returns (uint256 refundAmount) {
        if (msg.value < salePrice) {
            revert MarketplaceFees__InsufficientPayment();
        }

        FeeDistribution memory fees = this.calculateNonNFTFees(salePrice);

        // Transfer platform fee
        if (fees.platformFee > 0) {
            _safeTransferETH(fees.platformRecipient, fees.platformFee);
        }

        // Send remaining amount to escrow
        uint256 escrowAmount = salePrice - fees.platformFee;
        if (escrowAmount > 0) {
            escrowContract.lockFunds{value: escrowAmount}(listingId, seller, buyer);
            emit EscrowDeposit(listingId, escrowAmount, seller, buyer);
        }

        // Calculate refund
        refundAmount = msg.value - salePrice;

        emit FeesDistributed(
            salePrice,
            fees.platformFee,
            0,
            fees.platformRecipient,
            address(0),
            seller
        );
    }

    /**
     * @dev Process auction payment distribution
     * @param highestBid The highest bid amount in the auction
     * @param seller The address of the seller
     * @param nftContract The address of the NFT contract (if applicable)
     * @param tokenId The ID of the NFT being auctioned (if applicable)
     * @param isNFT Whether the auction is for an NFT or a non-NFT item
     * @param listingId The ID of the auction listing
     * @notice This function handles the payment distribution for auction winners, including platform fees, royalties, and seller payments.
     * It ensures that all fees are properly distributed and funds are transferred to the appropriate parties.
     */
    function processAuctionPayment(
        uint256 highestBid,
        address seller,
        address nftContract,
        uint256 tokenId,
        bool isNFT,
        uint256 listingId
    ) external payable {
        if (isNFT) {
            FeeDistribution memory fees = this.calculateNFTFees(
                highestBid,
                nftContract,
                tokenId
            );

            if (fees.platformFee > 0) {
                _safeTransferETH(fees.platformRecipient, fees.platformFee);
            }

            if (fees.royaltyAmount > 0) {
                _safeTransferETH(fees.royaltyRecipient, fees.royaltyAmount);
            }

            if (fees.sellerAmount > 0) {
                _safeTransferETH(seller, fees.sellerAmount);
            }

            emit FeesDistributed(
                highestBid,
                fees.platformFee,
                fees.royaltyAmount,
                fees.platformRecipient,
                fees.royaltyRecipient,
                seller
            );
        } else {
            FeeDistribution memory fees = this.calculateNonNFTFees(highestBid);

            if (fees.platformFee > 0) {
                _safeTransferETH(fees.platformRecipient, fees.platformFee);
            }

            uint256 escrowAmount = highestBid - fees.platformFee;
            if (escrowAmount > 0) {
                escrowContract.lockFunds{value: escrowAmount}(listingId, seller, msg.sender);
                emit EscrowDeposit(listingId, escrowAmount, seller, msg.sender);
            }

            emit FeesDistributed(
                highestBid,
                fees.platformFee,
                0,
                fees.platformRecipient,
                address(0),
                seller
            );
        }
    }

    /**
     * @dev Refund excess payment to buyer
     * @param buyer The address of the buyer
     * @param excessAmount The amount to refund
     * @notice This function is called to refund any excess payment made by the buyer after fees have been deducted.
     */
    function refundExcessPayment(address buyer, uint256 excessAmount) external {
        if (excessAmount > 0) {
            _safeTransferETH(buyer, excessAmount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Safe ETH transfer with proper error handling
     * @param to The recipient address
     * @param amount The amount of ETH to transfer
     * @notice This function attempts to transfer ETH and reverts if it fails.
     * It is used to ensure that all ETH transfers in the contract are handled safely.
     */
    function _safeTransferETH(address to, uint256 amount) internal {
        if (amount == 0) return;

        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) {
            revert MarketplaceFees__TransferFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get current platform fee configuration
     * @return feeBps Current fee in basis points
     * @return recipient Current fee recipient address
     */
    function getPlatformFeeConfig() external view returns (uint256 feeBps, address recipient) {
        return governanceContract.getFeeConfig();
    }

    /**
     * @dev Preview total fees for a given sale price and NFT
     * @param salePrice The total sale price of the NFT
     * @param nftContract The address of the NFT contract
     * @param tokenId The ID of the NFT being sold
     * @return totalFees Total fees including platform fee and royalty amount
     * @return platformFee The platform fee amount
     * @return royaltyAmount The royalty amount for the NFT
     * @return sellerReceives The amount the seller receives after fees
     * @notice This function allows users to preview the fees that will be applied to an NFT sale before proceeding with the transaction.
     */
    function previewNFTFees(
        uint256 salePrice,
        address nftContract,
        uint256 tokenId
    ) external view returns (
        uint256 totalFees,
        uint256 platformFee,
        uint256 royaltyAmount,
        uint256 sellerReceives
    ) {
        FeeDistribution memory fees = this.calculateNFTFees(salePrice, nftContract, tokenId);

        return (
            fees.platformFee + fees.royaltyAmount,
            fees.platformFee,
            fees.royaltyAmount,
            fees.sellerAmount
        );
    }

    /**
     * @dev Preview total fees for non-NFT sale
     * @param salePrice The total sale price of the item
     * @return totalFees Total fees including platform fee
     * @return platformFee The platform fee amount
     * @return sellerReceives The amount the seller receives after fees
     * @notice This function allows users to preview the fees that will be applied to a non-NFT sale before proceeding with the transaction.
     */
    function previewNonNFTFees(uint256 salePrice) external view returns (
        uint256 totalFees,
        uint256 platformFee,
        uint256 sellerReceives
    ) {
        FeeDistribution memory fees = this.calculateNonNFTFees(salePrice);

        return (
            fees.platformFee,
            fees.platformFee,
            fees.sellerAmount
        );
    }
}