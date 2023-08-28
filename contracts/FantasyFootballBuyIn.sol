pragma solidity ^0.8.0;

contract Contest {
  address payable[] public players;
  mapping(address => bool) public hasVoted;
  address payable public winner;
  uint256 public totalPot;

  constructor() {
    totalPot = 0;
  }

  function enterContenst() public payable{
    require(msg.value == 100 ether, "Please send exactly 100 ether to enter the contenst");
    players.push(payable(msg.sender));
    totalPot += msg.value;
  }

  function voteForWinner(address payable _player) public {
    require(hasVoted[msg.sender] == false, "you have already voted");
    require(_player != msg.sender, "You cannot vote for yourself");
    require(isPlayer(_player), "Invalud player address");

    hasVoted[msg.sender] = true;
    if (winner == address(0)){
      winner = _player;
    } else {
      uint256 currentVotes = getVotes(winner);
      uint256 newVotes = getVotes(_player);
      if (newVotes > currentVotes){
        winner = _player;
      }
    }
  }

  function distributePrize() public {
    require(winner != address(0), "No Winner has been selected");
    require(msg.sender == winner, "Only the winner can distribute the prize");

    uint256 prizeAmount = address(this).balance;
    winner.transfer(prizeAmount);
    totalPot = 0;
  }

  function isPlayer(address _player) private view returns (bool) {
    for (uint256 i=0; i<players.length; i++){
      if (players[i] == _player) {
        return true;
      }
    }
    return false;
  }

  function getVotes(address _player) private view returns (uint256) {
    uint256 votes = 0;
    for (uint256 j=0; j < players.length ;j++) {
      if (players[j] != _player && hasVoted[players[j]]) {
        votes++;
      }
    }
    return votes;
  }
}