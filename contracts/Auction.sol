pragma solidity ^0.8.7;

contract Auction {

  address payable public owner;
  address public highestBidder;
  uint256 public highestBid;
  uint256 public startTime;
  uint256 public endTime;

  constructor(uint256 startTime, uint256 endTime) {
    owner = payable(msg.sender);
    startTime = startTime;
    endTime = endTime;
  }

  function bid(uint256 amount) public {
    require(block.timestamp >= startTime, "Auction not yet started");
    require(block.timestamp <= endTime, "Auction has ended");
    require(amount > highestBid, "Bid must be higher than current bid");

    highestBidder = msg.sender;
    highestBid = amount;
  }

  function finalize() public {
    require(block.timestamp > endTime, "Auction has not ended");

    // Transfer the item to the highest bidder
    uint256 winnings = highestBid;
    payable(highestBidder).transfer(winnings);

    // Delete the contract
    selfdestruct(owner);
  }
}