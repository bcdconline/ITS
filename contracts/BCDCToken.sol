pragma solidity ^0.4.11;

import './ERC20.sol';
import './SafeMath.sol';

contract BCDCToken is SafeMath, ERC20 {

    /// Token related information
    string public constant name = "BCDC Token";
    string public constant symbol = "BCDC";
    uint256 public constant decimals = 18;  // decimal places

    /// Mapping of token balance and allowed address for each address with transfer limit
    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;

    //set of crowdsale contract
    address public crowdsale;

    function BCDCToken(address _crowdsale){
        crowdsale = _crowdsale;
    }

    /// @param to The address of the investor to check balance
    /// @return balance tokens of investor address
    function balanceOf(address who) constant returns (uint) {
        return balances[who];
    }

    /// @param owner The address of the account owning tokens
    /// @param spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address owner, address spender) constant returns (uint) {
        return allowed[owner][spender];
    }

    /// @notice Transfer `value` BCDC tokens from sender's account
    /// `msg.sender` to provided account address `to`.
    /// @notice This function is disabled during the funding. TODO
    /// @dev Required state: Success
    /// @param to The address of the recipient
    /// @param value The number of BCDC tokens to transfer
    /// @return Whether the transfer was successful or not
    function transfer(address to, uint value) returns (bool ok) {
        uint256 senderBalance = balanceOf[msg.sender];
        if ( senderBalance >= value && value > 0) {
            senderBalance = safeSub(senderBalance, value);
            balances[msg.sender] = senderBalance;
            balanceOf[to] = safeAdd(balanceOf[to], value);
            Transfer(msg.sender, to, value);
            return true;
        }
        return false;
    }

    /// @notice Transfer `value` BCDC tokens from sender 'from'
    /// to provided account address `to`.
    /// @notice This function is disabled during the funding.
    /// @dev Required state: Success
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param value The number of BCDC to transfer
    /// @return Whether the transfer was successful or not
    function transferFrom(address from, address to, uint value) returns (bool ok) {
        if (balances[from] >= value &&
            allowed[from][msg.sender] >= value &&
            value > 0)
        {
            balances[to] = safeAdd(balances[to], value);
            balances[from] = safeSub(balances[from], value);
            allowed[from][msg.sender] = safeSub(allowed[from][msg.sender], value);
            Transfer(from, to, value);
            return true;
        } else { return false; }
    }

    /// @notice `msg.sender` approves `spender` to spend `value` tokens
    /// @param spender The address of the account able to transfer the tokens
    /// @param value The amount of wei to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address spender, uint value) returns (bool ok) {
        allowed[msg.sender][spender] = value;
        Approval(msg.sender, spender, value);
        return true;
    }
    // don't just send ether to the contract expecting to get tokens
    function() payable { throw; }

}
