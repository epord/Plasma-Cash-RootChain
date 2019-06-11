var CryptoMon = artifacts.require("CryptoMons");
var RootChain = artifacts.require("RootChain");
var ValidatorManagerContract = artifacts.require("ValidatorManagerContract");


//Cryptomon <- RootChain <- VMC
module.exports = function(deployer) {
  deployer.deploy(ValidatorManagerContract).then(function() {
    return deployer.deploy(RootChain, ValidatorManagerContract.address).then(function() {
      return deployer.deploy(CryptoMon, RootChain.address);
    });
  });
};
