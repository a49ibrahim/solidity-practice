// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./SendValueWithFallbackWithdraw.sol";
import "./NFTMarketAuction.sol";

// import "./roles/FoundationAdminRole.sol";

/**
 * @notice Manages a reserve price auction for NFTs.
 */

contract MarketReserveAuction is ReentrancyGuardUpgradeable, NFTMarketAuction, SendValueWithFallbackWithdraw {
    //   using SafeMathUpgradeable for uint256;

    struct ReserveAuction {
        address nftContract;
        uint256 tokenId;
        address payable seller;
        uint256 duration;
        uint256 extensionDuration;
        uint256 endTime;
        address payable bidder;
        uint256 amount;
    }

    mapping(address => mapping(uint256 => uint256)) private nftContractToTokenIdToAuctionId;
    mapping(uint256 => ReserveAuction) private auctionIdToAuction;

    uint256 private _minPercentIncrementInBasisPoints;
    uint256 internal constant BASIS_POINTS = 10000;

    uint256 private _duration;

    // Cap the max duration so that overflows will not occur
    uint256 private constant MAX_MAX_DURATION = 1000 days;

    uint256 private constant EXTENSION_DURATION = 15 minutes;

    event ReserveAuctionConfigUpdated(
        uint256 minPercentIncrementInBasisPoints,
        uint256 maxBidIncrementRequirement,
        uint256 duration,
        uint256 extensionDuration,
        uint256 goLiveDate
    );

    event ReserveAuctionCreated(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 duration,
        uint256 extensionDuration,
        uint256 reservePrice,
        uint256 auctionId
    );
    event ReserveAuctionUpdated(uint256 indexed auctionId, uint256 reservePrice);
    event ReserveAuctionCanceled(uint256 indexed auctionId);
    event ReserveAuctionBidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount, uint256 endTime);
    event ReserveAuctionFinalized(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed bidder,
        uint256 f8nFee,
        uint256 creatorFee,
        uint256 ownerRev
    );
    event ReserveAuctionCanceledByAdmin(uint256 indexed auctionId, string reason);

    modifier onlyValidAuctionConfig(uint256 reservePrice) {
        require(reservePrice > 0, "MarketReserveAuction: Reserve price must be at least 1 wei");
        _;
    }

    constructor() {
        _initializeMarketReserveAuction();
    }

    /**
     * @notice Returns auction details for a given auctionId.
     */
    function getReserveAuction(uint256 auctionId) public view returns (ReserveAuction memory) {
        return auctionIdToAuction[auctionId];
    }

    /**
     * @notice Returns the auctionId for a given NFT, or 0 if no auction is found.
     * @dev If an auction is canceled, it will not be returned. However the auction may be over and pending finalization.
     */
    function getReserveAuctionIdFor(address nftContract, uint256 tokenId) public view returns (uint256) {
        return nftContractToTokenIdToAuctionId[nftContract][tokenId];
    }

    /**
     * @dev Returns the seller that put a given NFT into escrow,
     * or bubbles the call up to check the current owner if the NFT is not currently in escrow.
     */
    function _getSellerFor(address nftContract, uint256 tokenId) internal view virtual returns (address payable) {
        address payable seller = auctionIdToAuction[nftContractToTokenIdToAuctionId[nftContract][tokenId]].seller;
        if (seller == address(0)) {
            return payable(IERC721Upgradeable(nftContract).ownerOf(tokenId));
        }
        return seller;
    }

    /**
     * @notice Returns the current configuration for reserve auctions.
     */
    function getReserveAuctionConfig()
        public
        view
        returns (uint256 minPercentIncrementInBasisPoints, uint256 duration)
    {
        minPercentIncrementInBasisPoints = _minPercentIncrementInBasisPoints;
        duration = _duration;
    }

    function _initializeMarketReserveAuction() internal {
        _duration = 24 hours; // A sensible default value
    }

    // TODO: allow users to update maybe
    function _updateReserveAuctionConfig(uint256 minPercentIncrementInBasisPoints, uint256 duration) internal {
        require(
            minPercentIncrementInBasisPoints <= BASIS_POINTS,
            "MarketReserveAuction: Min increment must be <= 100%"
        );
        // Cap the max duration so that overflows will not occur
        require(duration <= MAX_MAX_DURATION, "MarketReserveAuction: Duration must be <= 1000 days");
        require(duration >= EXTENSION_DURATION, "MarketReserveAuction: Duration must be >= EXTENSION_DURATION");
        _minPercentIncrementInBasisPoints = minPercentIncrementInBasisPoints;
        _duration = duration;

        // We continue to emit unused configuration variables to simplify the subgraph integration.
        emit ReserveAuctionConfigUpdated(minPercentIncrementInBasisPoints, 0, duration, EXTENSION_DURATION, 0);
    }

    /**
     * @notice Creates an auction for the given NFT.
     * The NFT is held in escrow until the auction is finalized or canceled.
     */
    function createReserveAuction(
        address nftContract,
        uint256 tokenId,
        uint256 reservePrice
    ) public onlyValidAuctionConfig(reservePrice) nonReentrant {
        // If an auction is already in progress then the NFT would be in escrow and the modifier would have failed
        uint256 auctionId = _getNextAndIncrementAuctionId();
        nftContractToTokenIdToAuctionId[nftContract][tokenId] = auctionId;
        auctionIdToAuction[auctionId] = ReserveAuction(
            nftContract,
            tokenId,
            payable(msg.sender),
            _duration,
            EXTENSION_DURATION,
            0, // endTime is only known once the reserve price is met
            payable(address(0)), // bidder is only known once a bid has been placed
            reservePrice
        );

        IERC721Upgradeable(nftContract).transferFrom(msg.sender, address(this), tokenId);

        emit ReserveAuctionCreated(
            msg.sender,
            nftContract,
            tokenId,
            _duration,
            EXTENSION_DURATION,
            reservePrice,
            auctionId
        );
    }

    /**
     * @notice If an auction has been created but has not yet received bids, the configuration
     * such as the reservePrice may be changed by the seller.
     */
    function updateReserveAuction(uint256 auctionId, uint256 reservePrice) public onlyValidAuctionConfig(reservePrice) {
        ReserveAuction storage auction = auctionIdToAuction[auctionId];
        require(auction.seller == msg.sender, "MarketReserveAuction: Not your auction");
        require(auction.endTime == 0, "MarketReserveAuction: Auction in progress");

        auction.amount = reservePrice;

        emit ReserveAuctionUpdated(auctionId, reservePrice);
    }

    /**
     * @notice If an auction has been created but has not yet received bids, it may be canceled by the seller.
     * The NFT is returned to the seller from escrow.
     */
    function cancelReserveAuction(uint256 auctionId) public nonReentrant {
        ReserveAuction memory auction = auctionIdToAuction[auctionId];
        require(auction.seller == msg.sender, "MarketReserveAuction: Not your auction");
        require(auction.endTime == 0, "MarketReserveAuction: Auction in progress");

        delete nftContractToTokenIdToAuctionId[auction.nftContract][auction.tokenId];
        delete auctionIdToAuction[auctionId];

        IERC721Upgradeable(auction.nftContract).transferFrom(address(this), auction.seller, auction.tokenId);

        emit ReserveAuctionCanceled(auctionId);
    }

    /**
     * @notice A bidder may place a bid which is at least the value defined by `getMinBidAmount`.
     * If this is the first bid on the auction, the countdown will begin.
     * If there is already an outstanding bid, the previous bidder will be refunded at this time
     * and if the bid is placed in the final moments of the auction, the countdown may be extended.
     */
    function placeBid(uint256 auctionId) public payable nonReentrant {
        ReserveAuction storage auction = auctionIdToAuction[auctionId];
        require(auction.amount != 0, "MarketReserveAuction: Auction not found");

        if (auction.endTime == 0) {
            // If this is the first bid, ensure it's >= the reserve price
            require(auction.amount <= msg.value, "MarketReserveAuction: Bid must be at least the reserve price");
        } else {
            // If this bid outbids another, confirm that the bid is at least x% greater than the last
            require(auction.endTime >= block.timestamp, "MarketReserveAuction: Auction is over");
            require(auction.bidder != msg.sender, "MarketReserveAuction: You already have an outstanding bid");
            uint256 minAmount = _getMinBidAmountForReserveAuction(auction.amount);
            require(msg.value >= minAmount, "MarketReserveAuction: Bid amount too low");
        }

        if (auction.endTime == 0) {
            auction.amount = msg.value;
            auction.bidder = payable(msg.sender);
            // On the first bid, the endTime is now + duration
            auction.endTime = block.timestamp + auction.duration;
        } else {
            // Cache and update bidder state before a possible reentrancy (via the value transfer)
            uint256 originalAmount = auction.amount;
            address payable originalBidder = auction.bidder;
            auction.amount = msg.value;
            auction.bidder = payable(msg.sender);

            // When a bid outbids another, check to see if a time extension should apply.
            if (auction.endTime - block.timestamp < auction.extensionDuration) {
                auction.endTime = block.timestamp + auction.extensionDuration;
            }

            // Refund the previous bidder
            _sendValueWithFallbackWithdrawWithLowGasLimit(originalBidder, originalAmount);
        }

        emit ReserveAuctionBidPlaced(auctionId, msg.sender, msg.value, auction.endTime);
    }

    /**
     * @notice Once the countdown has expired for an auction, anyone can settle the auction.
     * This will send the NFT to the highest bidder and distribute funds.
     */
    function finalizeReserveAuction(uint256 auctionId) public nonReentrant {
        ReserveAuction memory auction = auctionIdToAuction[auctionId];
        require(auction.endTime > 0, "MarketReserveAuction: Auction was already settled");
        require(auction.endTime < block.timestamp, "MarketReserveAuction: Auction still in progress");

        delete nftContractToTokenIdToAuctionId[auction.nftContract][auction.tokenId];
        delete auctionIdToAuction[auctionId];

        // buyer gets the nft
        IERC721Upgradeable(auction.nftContract).transferFrom(address(this), auction.bidder, auction.tokenId);

        // for now we send the value to seller, this can be changed to add royalties, creator fees etc.
        _sendValueWithFallbackWithdrawWithMediumGasLimit(auction.seller, auction.amount);
        // TODO: distribute funds
        // (uint256 f8nFee, uint256 creatorFee, uint256 ownerRev) = _distributeFunds(
        //     auction.nftContract,
        //     auction.tokenId,
        //     auction.seller,
        //     auction.amount
        // );

        emit ReserveAuctionFinalized(auctionId, auction.seller, auction.bidder, 0, 0, auction.amount);
    }

    /**
     * @notice Returns the minimum amount a bidder must spend to participate in an auction.
     */
    function getMinBidAmount(uint256 auctionId) public view returns (uint256) {
        ReserveAuction storage auction = auctionIdToAuction[auctionId];
        if (auction.endTime == 0) {
            return auction.amount;
        }
        return _getMinBidAmountForReserveAuction(auction.amount);
    }

    /**
     * @dev Determines the minimum bid amount when outbidding another user.
     */
    function _getMinBidAmountForReserveAuction(uint256 currentBidAmount) private view returns (uint256) {
        uint256 minIncrement = (currentBidAmount * _minPercentIncrementInBasisPoints) / BASIS_POINTS;
        if (minIncrement == 0) {
            // The next bid must be at least 1 wei greater than the current.
            return currentBidAmount + 1;
        }
        return minIncrement + currentBidAmount;
    }

    // TODO: protect function with ownable
    /**
     * @notice Allows Foundation to cancel an auction, refunding the bidder and returning the NFT to the seller.
     * This should only be used for extreme cases such as DMCA takedown requests. The reason should always be provided.
     */
    // function adminCancelReserveAuction(uint256 auctionId, string memory reason) public {
    //     require(bytes(reason).length > 0, "MarketReserveAuction: Include a reason for this cancellation");
    //     ReserveAuction memory auction = auctionIdToAuction[auctionId];
    //     require(auction.amount > 0, "MarketReserveAuction: Auction not found");

    //     delete nftContractToTokenIdToAuctionId[auction.nftContract][auction.tokenId];
    //     delete auctionIdToAuction[auctionId];

    //     IERC721Upgradeable(auction.nftContract).transferFrom(address(this), auction.seller, auction.tokenId);
    //     if (auction.bidder != address(0)) {
    //         _sendValueWithFallbackWithdrawWithMediumGasLimit(auction.bidder, auction.amount);
    //     }

    //     emit ReserveAuctionCanceledByAdmin(auctionId, reason);
    // }
}