pragma solidity ^0.4.11;

import './ERC20.sol';
import './SafeMath.sol';
import './MultiSigWallet.sol';

// BCDC Token Contract with Token Sale Functionality as well
contract BCDCToken is SafeMath, ERC20 {

    /// Is BCDC Token Initalized
    bool public isBCDCToken = false;

    /// Define the current state of crowdsale
    enum State{PreFunding, Funding, Success, Failure}

    /// Token related information
    string public constant name = "BCDC Token";
    string public constant symbol = "BCDC";
    uint256 public constant decimals = 18;  // decimal places

    /// Mapping of token balance and allowed address for each address with transfer limit
    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;

    // Crowdsale information
    bool public finalizedCrowdfunding = false;
    uint256 public fundingStartBlock; // crowdsale start block
    uint256 public fundingEndBlock; // crowdsale end block
    uint256 public tokenSaleMax; // Max token allowed to sale e.g.250 millions + 125 millions for early investors
    uint256 public tokenSaleMin; // Min tokens needs to be sold out for success
    //1 Billion BCDC Tokens
    uint256 public constant maxTokenSupply = 1000000000;

    /// Multisig Wallet Address
    address public bcdcMultisig;
    /// BCDC's time-locked vault
    /// BCDCVault public timeVault;

    /// BCDC:ETH exchange rate
    uint256 tokensPerEther;

    function BCDCToken(address _bcdcMultiSig,
                      //address _upgradeMaster,
                      uint256 _fundingStartBlock,
                      uint256 _fundingEndBlock,
                      uint256 _tokenSaleMax,
                      uint256 _tokenSaleMin,
                      uint256 _tokensPerEther) {

        if (_bcdcMultiSig == 0) throw;
        //if (_upgradeMaster == 0) throw;
        if (_fundingStartBlock <= block.number) throw;
        if (_fundingEndBlock   <= _fundingStartBlock) throw;
        if (_tokenSaleMax <= _tokenSaleMin) throw;
        if (_tokensPerEther == 0) throw;
        isBCDCToken = true;
        //upgradeMaster = _upgradeMaster;
        fundingStartBlock = _fundingStartBlock;
        fundingEndBlock = _fundingEndBlock;
        tokenSaleMax = _tokenSaleMax;
        tokenSaleMin = _tokenSaleMin;
        tokensPerEther = _tokensPerEther;
        //timeVault = new BCDCVault(_bcdcMultiSig);
        //if (!timeVault.isBCDCVault()) throw;
        bcdcMultisig = _bcdcMultiSig;
        if (!MultiSigWallet(bcdcMultisig).isMultiSigWallet()) throw;
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
        if (getState() != State.Success) throw; // Abort if crowdfunding was not a success.
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
        if (getState() != State.Success) throw; // Abort if crowdfunding was not a success.
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
        if (getState() != State.Success) throw; // Abort if not in Success state.
        allowed[msg.sender][spender] = value;
        Approval(msg.sender, spender, value);
        return true;
    }

    // Set of Crowdfunding Functions :
    // Don't just send ether to the contract expecting to get tokens
    function() payable { throw; }

    /// Sale of the tokens. Investors can call this method to invest into BCDC Tokens
    /// Only when it's in funding mode
    function sale() payable external {
        // Allow only to invest in funding state
        if (getState() != State.Funding) throw;

        // Sorry !! We do not allow to invest with 0 as value
        if (msg.value == 0) throw;

        // multiply by exchange rate to get newly created token amount
        uint256 createdTokens = safeMul(msg.value, tokensPerEther);

        // Wait we crossed maximum token sale goal. It's successful token sale !!
        if (safeAdd(createdTokens, totalSupply) > tokenSaleMax) throw;

        // Call to Internal function to assign tokens
        assignTokens(msg.sender, createdTokens);
    }

    // BCDC accepts Early Investment and Pre ITS through manual process in Fiat Currency
    // BCDC Team will assign the tokens to investors manually through this function
    function earlyInvestor(address earlyInvestor, uint256 assignTokens) onlyOwner external {
        // Allow only in Pre Funding Mode
        if (getState() != State.PreFunding) throw;

        // By mistake tokens mentioned as 0, save the cost of assigning tokens.
        if (assignTokens == 0 ) throw;

        assignTokens(earlyInvestor, assignTokens);
    }

    // Function will transfer the tokens to investor's address
    // Common function code for Early Investor and Crowdsale Investor
    function assignTokens(address investor, uint256 tokens) internal {
        // Creating tokens and  increasing the totalSupply
        totalSupply = safeAdd(totalSupply, tokens);

        // Assign new tokens to the sender
        balances[investor] = safeAdd(balances[investor], tokens);

        // Finally token created for sender, log the creation event
        Transfer(0, investor, tokens);
    }

    /// Finalize crowdfunding
    /// Finally - Transfer the Ether to Multisig Wallet
    function finalizeCrowdfunding() external {
        // Abort if not in Funding Success state.
        if (getState() != State.Success) throw; // don't finalize unless we won
        if (finalizedCrowdfunding) throw; // can't finalize twice (so sneaky!)

        // prevent more creation of tokens
        finalizedCrowdfunding = true;

        //TODO - Do complex code here

        // Transfer ETH to the BCDC Multisig address.
        if (!bcdcMultisig.send(this.balance)) throw;
    }

    /// Call this function to get the refund of investment done during Crowdsale
    /// Refund can be done only when Min Goal has not reached and Crowdsale is over
    function refund() external {
        // Abort if not in Funding Failure state.
        if (getState() != State.Failure) throw;

        uint256 bcdcValue = balances[msg.sender];
        if (bcdcValue == 0) throw;
        balances[msg.sender] = 0;
        totalSupply = safeSub(totalSupply, bcdcValue);

        uint256 ethValue = safeDiv(bcdcValue, tokensPerEther);
        Refund(msg.sender, ethValue);
        if (!msg.sender.send(ethValue)) throw;
    }

    /// This is to change the price of BCDC Tokens per ether
    /// Only owner can change
    /// To motivate the investors with discounted rate pricing changes over weeks
    function changeExchangePrice(uint256 _changedPrice) onlyOwner external  {
        // Allow only to set the price while in funding state
        if (getState() != State.Funding) throw;
        tokensPerEther = _changedPrice;
    }

    /// This will return the current state of Token Sale
    /// Read only method so no transaction fees
    function getState() public constant returns (State){
      if (block.number < fundingStartBlock) return State.PreFunding;
      else if (block.number <= fundingEndBlock && totalSupply < tokenSaleMax) return State.Funding;
      else if (totalSupply >= tokenSaleMin) return State.Success;
      else return State.Failure;
    }
}
