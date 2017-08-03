let BCDCToken = artifacts.require("BCDCToken");
let MultiSigWallet = artifacts.require("MultiSigWallet");
let SafeMath = artifacts.require("SafeMath");

module.exports = function(deployer,network) {

  let safeMath,token,wallet;
  let signaturesRequired = 2;
  let accounts = web3.eth.accounts.slice(0,3);

  if(network == 'testnet'){
    deployer.deploy(MultiSigWallet,accounts,signaturesRequired).then(function(instance){
      wallet = instance;
      let startBlock = web3.eth.blockNumber + 10;
      let priceChangeBlock = startBlock + 10000;
      let endBlock = web3.eth.blockNumber + 20000;
      let tokensPerEther = 2500;
      let tokenSaleMax = 5000000;
      let tokenSaleMin = 500000;
      console.log("address of multisig:"+MultiSigWallet.address);
      return deployer.deploy(BCDCToken,MultiSigWallet.address,startBlock,endBlock,priceChangeBlock,tokenSaleMax,tokenSaleMin,tokensPerEther);
    }).then(function(){
      BCDCToken.deployed();
    }).then(function(instance){
      token = instance;
    });
  }
  else if (network == 'mainnet') {
    MultiSigWallet.at(MultiSigWallet.address).then(function(instance){
      wallet = instance;
      let startBlock = web3.eth.blockNumber + 10;
      let priceChangeBlock = startBlock + 10000;
      let endBlock = web3.eth.blockNumber + 20000;
      let tokensPerEther = 2500;
      let tokenSaleMax = 5000000;
      let tokenSaleMin = 500000;
      return deployer.deploy(BCDCToken,MultiSigWallet.address,startBlock,endBlock,priceChangeBlock,tokenSaleMax,tokenSaleMin,tokensPerEther);
    }).then(function(){
      BCDCToken.deployed();
    }).then(function(instance){
      token = instance;
    });

  }
};
