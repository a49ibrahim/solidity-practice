// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.3;

/**
 * @notice An abstraction layer for auctions.
 * @dev This contract can be expanded with reusable calls and data as more auction types are added.
 */
abstract contract MarketAuction {
    /**
     * @dev A global id for auctions of any type.
     */
    uint256 private nextAuctionId;

    function _initializeMarketAuction() internal {
        nextAuctionId = 1;
    }

    function _getNextAndIncrementAuctionId() internal returns (uint256) {
        return nextAuctionId++;
    }

    uint256[1000] private ______gap;
}