pragma solidity ^0.4.11;

import './SafeMath.sol';
import './BCDCToken.sol';

// @title BCDC Token vault, locked tokens for 1 month (Dev Team) and 1 year for Founders
contract BCDCVault is SafeMath {

    // flag to determine if address is for a real contract or not
    bool public isBCDCVault = false;

    BCDCToken bcdcToken;
    address bcdcMultisig;
    uint256 unlockedBlockForDev;
    uint256 unlockedBlockForFounders;
    // It should be 1 * 30 days * 24 hours * 60 minutes * 60 seconds / 17
    // We can set small for testing purpose
    uint256 public constant numBlocksLockedDev = 12;
    // It should be 12 months * 30 days * 24 hours * 60 minutes * 60 seconds / 17
    // We can set small for testing purpose
    uint256 public constant numBlocksLockedFounders = 144;
    //
    bool unlockedAllTokensForDev = false;
    bool unlockedAllTokensForFounders = false;

    // ** Constructor function sets the BCDC Multisig address and
    // total number of locked tokens to transfer
    function BCDCVault(address _bcdcMultisig) {
        if (_bcdcMultisig == 0x0) throw;
        bcdcToken = BCDCToken(msg.sender);
        bcdcMultisig = _bcdcMultisig;
        isBCDCVault = true;
        unlockedBlockForDev = safeAdd(block.number, numBlocksLockedDev); // 30 days of blocks later
        unlockedBlockForFounders = safeAdd(block.number, numBlocksLockedFounders); // 365 days of blocks later
    }

    // ** Transfer Development Team Tokens To MultiSigWallet - 30 Days Locked
    function unlockForDevelopment() external {
        // If it has not reached 30 days mark do not transfer
        if (block.number < unlockedBlockForDev) throw;
        // If it is already unlocked then do not allowed
        if (unlockedAllTokensForDev) throw;
        // Mark it as unlocked
        unlockedAllTokensForDev = true;
        // Will fail if allocation (and therefore toTransfer) is 0.
        uint256 totalBalance = bcdcToken.balanceOf(this);
        uint256 developmentTokens = safeDiv(safeMul(totalBalance, 50), 100);
        if (!bcdcToken.transfer(bcdcMultisig, developmentTokens)) throw;
    }

    // ** Transfer Founders Team Tokens To MultiSigWallet - 365 Days Locked
    function unlockForFounders() external {
        // If it has not reached 365 days mark do not transfer
        if (block.number < unlockedBlockForFounders) throw;
        // If it is already unlocked then do not allowed
        if (unlockedAllTokensForFounders) throw;
        // Mark it as unlocked
        unlockedAllTokensForFounders = true;
        // Will fail if allocation (and therefore toTransfer) is 0.
        if (!bcdcToken.transfer(bcdcMultisig, bcdcToken.balanceOf(this))) throw;
        // So that ether will not be trapped here.
        if (!bcdcMultisig.send(this.balance)) throw;
    }

    // disallow payment after unlock block
    function () payable {
        if (block.number >= unlockedBlockForFounders) throw;
    }

}
