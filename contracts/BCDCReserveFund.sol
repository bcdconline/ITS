pragma solidity ^0.4.11;

import './BCDCToken.sol';

contract BCDCReserveFund {
    // BCDC token that will used in claim
    BCDCToken bcdcToken;

    // Address of Owner for this Contract
    address public owner;

    // Total claimed tokens
    uint256 public totalClaimed;

    // Events to be tracked
    event Claimed(address indexed claimAddress, uint tokens);

    function BCDCReserveFund(address _bcdcToken) {
        // check if bcdctoken address is proper or not
        if (_bcdcToken == 0x0) throw;
        // Get the instance of BCDCToken
        bcdcToken = BCDCToken(_bcdcToken);
        // Set the owner who deployed this contract
        owner = msg.sender;
    }

    // Ownership related modifer and functions
    // @dev Throws if called by any account other than the owner
    modifier onlyOwner() {
      if (msg.sender != owner) {
        throw;
      }
      _;
    }

    // @dev Allows the current owner to transfer control of the contract to a newOwner.
    // @param newOwner The address to transfer ownership to.
    function transferOwnership(address newOwner) onlyOwner {
      if (newOwner != address(0)) {
        owner = newOwner;
      }
    }

    // To claim the token of rewards against the recycling or something else
    // @dev Allow to transfer the reward to token to motivate to save the planet
    // @param claimAddress ethereum address to be Claimed
    // @param claimTokens tokens to be claimed to claimAddress
    function claimToken(address claimAddress, uint256 claimTokens) external onlyOwner {
        // Check the balance of tokens owned by Reservefund
        uint256 balance = bcdcToken.balanceOf(this);
        if (claimTokens > balance) throw;
        // Transfer the tokens to claimAddress with special functions
        if (!bcdcToken.reserveTokenClaim( claimAddress, claimTokens)) throw;
        // Log the event
        Claimed(claimAddress, claimTokens);
    }

}
