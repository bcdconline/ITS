pragma solidity ^0.4.11;

import './ERC20.sol';
import './SafeMath.sol';
import './MultiSigWallet.sol';
import './Haltable.sol';
import './BCDCVault.sol';

contract UpgradeAgent is SafeMath {
  address public owner;
  bool public isUpgradeAgent;
  function upgradeFrom(address _from, uint256 _value) public;
  function finalizeUpgrade() public;
  function setOriginalSupply() public;
}
// BCDC Token Contract with Token Sale Functionality as well
contract BCDCToken is SafeMath, ERC20, Haltable {

    // Is BCDC Token Initalized
    bool public isBCDCToken = false;

    // Define the current state of crowdsale
    enum State{PreFunding, Funding, Success, Failure}

    // Token related information
    string public constant name = "BCDC Token";
    string public constant symbol = "BCDC";
    uint256 public constant decimals = 18;  // decimal places

    // Mapping of token balance and allowed address for each address with transfer limit
    mapping (address => uint256) balances;
    // This is only for refund purpose, as we have price range during different weeks of Crowdfunding,
    //  need to maintain total investment done so refund would be exactly same.
    mapping (address => uint256) investment;
    mapping (address => mapping (address => uint256)) allowed;

    // Crowdsale information
    bool public finalizedCrowdfunding = false;
    bool public preallocated = false;
    uint256 public fundingStartBlock; // crowdsale start block
    uint256 public fundingEndBlock; // crowdsale end block
    uint256 public priceChangeBlock;
    // Upgraded Token Related
    bool public finalizedUpgrade = false;
    address public upgradeMaster;
    UpgradeAgent public upgradeAgent;
    uint256 public totalUpgraded;
    // Maximum Token Sale (Crowdsale + Early Sale + Supporters)
    // Approximate 250 millions ITS + 125 millions for early investors + 75 Millions to Supports
    uint256 public tokenSaleMax;
    // Min tokens needs to be sold out for success
    // Approximate 1/4 of 250 millions
    uint256 public tokenSaleMin;
    //1 Billion BCDC Tokens
    uint256 public constant maxTokenSupply = 1000000000;
    // Team token percentages to store in time vault
    uint256 public constant vaultPercentOfTotal = 5;
    // Project Reserved Fund Token %
    uint256 public constant reservedPercentTotal = 25;

    // Multisig Wallet Address
    address public bcdcMultisig;
    // Project Reserve Fund address
    address bcdcReserveFund;
    // BCDC's time-locked vault
    BCDCVault public timeVault;

    // Events
    event Upgrade(address indexed _from, address indexed _to, uint256 _value);
    event Refund(address indexed _from, uint256 _value);
    event UpgradeFinalized(address sender, address upgradeAgent);
    event UpgradeAgentSet(address agent);

    // BCDC:ETH exchange rate
    uint256 tokensPerEther;

    function BCDCToken(address _bcdcMultiSig,
                      address _upgradeMaster,
                      uint256 _fundingStartBlock,
                      uint256 _fundingEndBlock,
                      uint256 _priceChangeBlock,
                      uint256 _tokenSaleMax,
                      uint256 _tokenSaleMin,
                      uint256 _tokensPerEther) {

        if (_bcdcMultiSig == 0) throw;
        if (_upgradeMaster == 0) throw;
        if (_fundingStartBlock <= block.number) throw;
        if (_priceChangeBlock  <= _fundingStartBlock) throw;
        if (_fundingEndBlock   <= _fundingStartBlock) throw;
        if (_fundingEndBlock   <= _priceChangeBlock) throw;
        if (_tokenSaleMax <= _tokenSaleMin) throw;
        if (_tokensPerEther == 0) throw;
        isBCDCToken = true;
        upgradeMaster = _upgradeMaster;
        fundingStartBlock = _fundingStartBlock;
        fundingEndBlock = _fundingEndBlock;
        priceChangeBlock = _priceChangeBlock;
        tokenSaleMax = _tokenSaleMax;
        tokenSaleMin = _tokenSaleMin;
        tokensPerEther = _tokensPerEther;
        timeVault = new BCDCVault(_bcdcMultiSig);
        if (!timeVault.isBCDCVault()) throw;
        bcdcMultisig = _bcdcMultiSig;
        if (!MultiSigWallet(bcdcMultisig).isMultiSigWallet()) throw;
    }
    // @param Address of Contract of Ether Address for Project Reserve Fund
    // This has to be called before preAllocation
    // Only to be called by Owner of this contract
    function setBcdcReserveFund(address _bcdcReserveFund) onlyOwner{
        if (getState() != State.PreFunding) throw;        
        if (preallocated) throw; // Has to be done before preallocation
        if (_bcdcReserveFund == 0x0) throw;
        bcdcReserveFund = _bcdcReserveFund;
    }

    // @param to The address of the investor to check balance
    // @return balance tokens of investor address
    function balanceOf(address who) constant returns (uint) {
        return balances[who];
    }

    // @param to The address of the investor to check investment amount
    // @return total investment done by ethereum address
    // This method is only usable up to Crowdfunding ends (Success or Fail)
    // So if tokens are transfered post crowdsale investment will not change.
    function checkInvestment(address who) constant returns (uint) {
        return investment[who];
    }

    // @param owner The address of the account owning tokens
    // @param spender The address of the account able to transfer the tokens
    // @return Amount of remaining tokens allowed to spent
    function allowance(address owner, address spender) constant returns (uint) {
        return allowed[owner][spender];
    }

    // ** Transfer `value` BCDC tokens from sender's account
    // `msg.sender` to provided account address `to`.
    // ** This function is disabled during the funding. TODO
    // @dev Required state: Success
    // @param to The address of the recipient
    // @param value The number of BCDC tokens to transfer
    // @return Whether the transfer was successful or not
    function transfer(address to, uint value) returns (bool ok) {
        if (getState() != State.Success) throw; // Abort if crowdfunding was not a success.
        uint256 senderBalance = balances[msg.sender];
        if ( senderBalance >= value && value > 0) {
            senderBalance = safeSub(senderBalance, value);
            balances[msg.sender] = senderBalance;
            balances[to] = safeAdd(balances[to], value);
            Transfer(msg.sender, to, value);
            return true;
        }
        return false;
    }

    // ** Transfer `value` BCDC tokens from sender 'from'
    // to provided account address `to`.
    // ** This function is disabled during the funding.
    // @dev Required state: Success
    // @param from The address of the sender
    // @param to The address of the recipient
    // @param value The number of BCDC to transfer
    // @return Whether the transfer was successful or not
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

    // ** `msg.sender` approves `spender` to spend `value` tokens
    // @param spender The address of the account able to transfer the tokens
    // @param value The amount of wei to be approved for transfer
    // @return Whether the approval was successful or not
    function approve(address spender, uint value) returns (bool ok) {
        if (getState() != State.Success) throw; // Abort if not in Success state.
        allowed[msg.sender][spender] = value;
        Approval(msg.sender, spender, value);
        return true;
    }

    // Token upgrade functionality

    // ** Upgrade tokens to the new token contract.
    // @dev Required state: Success
    // @param value The number of tokens to upgrade
    function upgrade(uint256 value) external {
        if (getState() != State.Success) throw; // Abort if not in Success state.
        if (upgradeAgent.owner() == 0x0) throw; // need a real upgradeAgent address
        if (finalizedUpgrade) throw; // cannot upgrade if finalized

        // Validate input value.
        if (value == 0) throw;
        if (value > balances[msg.sender]) throw;

        // update the balances here first before calling out (reentrancy)
        balances[msg.sender] = safeSub(balances[msg.sender], value);
        totalSupply = safeSub(totalSupply, value);
        totalUpgraded = safeAdd(totalUpgraded, value);
        upgradeAgent.upgradeFrom(msg.sender, value);
        Upgrade(msg.sender, upgradeAgent, value);
    }

    // ** Set address of upgrade target contract and enable upgrade
    // process.
    // @dev Required state: Success
    // @param agent The address of the UpgradeAgent contract
    function setUpgradeAgent(address agent) external {
        if (getState() != State.Success) throw; // Abort if not in Success state.
        if (agent == 0x0) throw; // don't set agent to nothing
        if (msg.sender != upgradeMaster) throw; // Only a master can designate the next agent
        upgradeAgent = UpgradeAgent(agent);
        if (!upgradeAgent.isUpgradeAgent()) throw;
        // this needs to be called in success condition to guarantee the invariant is true
        upgradeAgent.setOriginalSupply();
        UpgradeAgentSet(upgradeAgent);
    }

    // ** Set address of upgrade target contract and enable upgrade
    // process.
    // @dev Required state: Success
    // @param master The address that will manage upgrades, not the upgradeAgent contract address
    function setUpgradeMaster(address master) external {
        if (getState() != State.Success) throw; // Abort if not in Success state.
        if (master == 0x0) throw;
        if (msg.sender != upgradeMaster) throw; // Only a master can designate the next master
        upgradeMaster = master;
    }

    // ** finalize the upgrade
    // @dev Required state: Success
    function finalizeUpgrade() external {
        if (getState() != State.Success) throw; // Abort if not in Success state.
        if (upgradeAgent.owner() == 0x0) throw; // we need a valid upgrade agent
        if (msg.sender != upgradeMaster) throw; // only upgradeMaster can finalize
        if (finalizedUpgrade) throw; // can't finalize twice

        finalizedUpgrade = true; // prevent future upgrades

        upgradeAgent.finalizeUpgrade(); // call finalize upgrade on new contract
        UpgradeFinalized(msg.sender, upgradeAgent);
    }

    // Set of Crowdfunding Functions :
    // Don't just send ether to the contract expecting to get tokens
    function() payable { throw; }

    // Sale of the tokens. Investors can call this method to invest into BCDC Tokens
    // Only when it's in funding mode. In case of emergecy it will be halted.
    function sale() payable stopIfHalted external {
        // Allow only to invest in funding state
        if (getState() != State.Funding) throw;

        // Sorry !! We do not allow to invest with 0 as value
        if (msg.value == 0) throw;

        // multiply by exchange rate to get newly created token amount
        uint256 createdTokens = safeMul(msg.value, getTokensPerEtherPrice());

        // Wait we crossed maximum token sale goal. It's successful token sale !!
        if (safeAdd(createdTokens, totalSupply) > tokenSaleMax) throw;

        // Call to Internal function to assign tokens
        assignTokens(msg.sender, createdTokens);

        // Track the investment for each address till crowdsale ends
        investment[msg.sender] = safeAdd(investment[msg.sender], msg.value);
    }

    // To allocate tokens to Project Fund - eg. RecycleToCoin before Token Sale
    // Tokens allocated to these will not be count in totalSupply till the Token Sale Success and Finalized in finalizeCrowdfunding()
    function preAllocation() onlyOwner stopIfHalted external {
        // Allow only in Pre Funding Mode
        if (getState() != State.PreFunding) throw;
        // Check if BCDC Reserve Fund is set or not
        if (bcdcReserveFund == 0x0) throw;
        // To prevent multiple call by mistake
        if (preallocated) throw;
        preallocated = true;
        // 25% of overall Token Supply to project reseve fund
        uint256 projectTokens = safeDiv(safeMul(maxTokenSupply, reservedPercentTotal), 100);
        // At this time we will not add to totalSupply because these are not part of Sale
        // It will be added in totalSupply once the Token Sale is Finalized
        balances[bcdcReserveFund] = projectTokens;
        // Log the event
        Transfer(0, bcdcReserveFund, projectTokens);
    }

    // BCDC accepts Early Investment through manual process in Fiat Currency
    // BCDC Team will assign the tokens to investors manually through this function
    function earlyInvestment(address earlyInvestor, uint256 assignedTokens, uint256 etherValue) onlyOwner stopIfHalted external {
        // Allow only in Pre Funding Mode
        if (getState() != State.PreFunding) throw;

        // By mistake tokens mentioned as 0, save the cost of assigning tokens.
        if (assignedTokens == 0 ) throw;

        // Call to Internal function to assign tokens
        assignTokens(earlyInvestor, assignedTokens);

        // Track the investment for each address
        investment[earlyInvestor] = safeAdd(investment[earlyInvestor], etherValue);
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

    // Finalize crowdfunding
    // Finally - Transfer the Ether to Multisig Wallet
    function finalizeCrowdfunding() stopIfHalted external {
        // Abort if not in Funding Success state.
        if (getState() != State.Success) throw; // don't finalize unless we won
        if (finalizedCrowdfunding) throw; // can't finalize twice (so sneaky!)

        // prevent more creation of tokens
        finalizedCrowdfunding = true;

        // Check if Unsold tokens out 450 millions
        // 250 Millions Sale + 125 Millions for Early Investors + 75 Millions for Supporters
        uint256 unsoldTokens = safeSub(tokenSaleMax, totalSupply);

        // Founders and Tech Team Tokens Goes to Vault, Locked for 1 month (Tech) and 1 year(Team)
        uint256 vaultTokens = safeDiv(safeMul(maxTokenSupply, vaultPercentOfTotal), 100);
        totalSupply = safeAdd(totalSupply, vaultTokens);
        balances[timeVault] = safeAdd(balances[timeVault], vaultTokens);
        Transfer(0, timeVault, vaultTokens);

        // Only transact if there are any unsold tokens
        if(unsoldTokens > 0) {
            totalSupply = safeAdd(totalSupply, unsoldTokens);
            // 50% unsold tokens assign to Reward tokens held by Multisig Wallet
            uint256 rewardTokens = safeDiv(safeMul(unsoldTokens, 50), 100);
            balances[bcdcMultisig] = safeAdd(balances[bcdcMultisig], rewardTokens);// Assign Reward Tokens to Multisig wallet
            Transfer(0, bcdcMultisig, rewardTokens);
            // Remaining unsold tokens assign to Project Reserve Fund
            uint256 projectTokens = safeSub(unsoldTokens, rewardTokens);
            balances[bcdcReserveFund] = safeAdd(balances[bcdcReserveFund], projectTokens);// Assign Reward Tokens to Multisig wallet
            Transfer(0, bcdcReserveFund, projectTokens);
        }

        // Add pre allocated tokens to project reserve fund to totalSupply
        uint256 preallocatedTokens = safeDiv(safeMul(maxTokenSupply, reservedPercentTotal), 100);
        // project tokens already counted, so only add preallcated tokens
        totalSupply = safeAdd(totalSupply, preallocatedTokens);
        // Allocate total project tokens - To reduce the transaction both counted together
        balances[bcdcReserveFund] = safeAdd(balances[bcdcReserveFund], preallocatedTokens);
        Transfer(0, bcdcReserveFund, preallocatedTokens);
        // Total Supply Should not be greater than 1 Billion
        if (totalSupply > maxTokenSupply) throw;
        // Transfer ETH to the BCDC Multisig address.
        if (!bcdcMultisig.send(this.balance)) throw;
    }

    // Call this function to get the refund of investment done during Crowdsale
    // Refund can be done only when Min Goal has not reached and Crowdsale is over
    function refund() external {
        // Abort if not in Funding Failure state.
        if (getState() != State.Failure) throw;

        uint256 bcdcValue = balances[msg.sender];
        if (bcdcValue == 0) throw;
        balances[msg.sender] = 0;
        totalSupply = safeSub(totalSupply, bcdcValue);

        uint256 ethValue = investment[msg.sender];
        investment[msg.sender] = 0;
        Refund(msg.sender, ethValue);
        if (!msg.sender.send(ethValue)) throw;
    }

    // This function will return constant price of Tokens Per Ether
    // Initially it will be different then it will be reduced
    // To motivate the investors with discounted rate pricing changes over weeks
    function getTokensPerEtherPrice() public constant returns (uint256){
        // Allow only to set the price while in funding state
        if (getState() != State.Funding) throw;
        // It will be 2 weeks from start of sale
        if (block.number < priceChangeBlock) return tokensPerEther;
        else return safeSub(tokensPerEther, 500);
    }

    // This will return the current state of Token Sale
    // Read only method so no transaction fees
    function getState() public constant returns (State){
      if (block.number < fundingStartBlock) return State.PreFunding;
      else if (block.number <= fundingEndBlock && totalSupply < tokenSaleMax) return State.Funding;
      else if (totalSupply >= tokenSaleMin) return State.Success;
      else return State.Failure;
    }
}
