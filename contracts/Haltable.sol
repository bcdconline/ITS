pragma solidity ^0.4.11;

import './Ownable.sol';
/**
** @title Haltable
** @dev Created for Crowdsale Contract to be halted for some time in case of any issues during the Crowdsale
** @implementation Ownable contract so that state can be changed only by Owner.
**/
contract Haltable is Ownable {

    /** state variable to define halt situation **/
    bool public halted;

    /** Use this as function modifier that should not execute if contract state Halted **/
    modifier stopIfHalted {
      if(halted) throw;
      _;
    }

    /** Use this as function modifier that should execute only if contract state Halted **/
    modifier runIfHalted{
      if(!halted) throw;
      _;
    }

    /** called by only owner in case of any emergecy situation **/
    function halt() external onlyOwner{
      halted = true;
    }

    /** called by only owner to stop the emergency situation **/
    function unhalt() external onlyOwner{
      halted = false;
    }
    
}
