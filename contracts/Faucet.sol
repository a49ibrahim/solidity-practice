// SPDX-License-Identifier: CC-BY-SA-4.0

// Version of Solidity compiler this program was written for
pragma solidity ^0.6.4;

contract Owned {
  address payable owner;

  //contract constructor; set owner
  constructor() public {
    owner = msg.sender;
  }

  //Access control modifier
  modifier onlyOwner() {
    require(
      msg.sender == owner,
      "only the contract owner can call this function"
    );
    _;
  }
}

contract Mortal is Owned {
  //Contract destructor
  function destroy() public onlyOwner {
    selfdestruct(owner);
  }
}

contract Faucet is Mortal {
  event Withdrawal(address indexed to, unint amount);
  event Deposit(address indexed from, uint amount);

  //Accept  any incoming amount
  receive() external payable {
    emit Deposit(msg.sender, msg.value);
  }

  //Gice out ether to anyone who asks
  function Withdrawal(uint Withdraw_amount) {
    require(Withdraw_amount <= 0.1 ether);

    require(
      address(this).balance >= Withdraw_amount,
      "Insufficent balance in faucet for withdrawal request"
    );

    //Send the amount to the address that requested it
    msg.sender.transfer(withdraw_amount);

    emit Withdrawal(msg.sender, withdrawal_amount);
  }
}
