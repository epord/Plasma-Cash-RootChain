var CryptoMon = artifacts.require("CryptoMons");
var RootChain = artifacts.require("RootChain");
var ValidatorManagerContract = artifacts.require("ValidatorManagerContract");
var plasmaCM = artifacts.require("PlasmaCM");
var adjudicators = artifacts.require("Adjudicators");
var state = artifacts.require("State");

//Cryptomon <- RootChain <- VMC
module.exports = function(deployer) {
  deployer.deploy(ValidatorManagerContract).then(function() {
    return deployer.deploy(RootChain, ValidatorManagerContract.address).then(function() {
      return deployer.deploy(CryptoMon, RootChain.address).then(async function() {
        await deployer.deploy(state);
        await deployer.link(state, adjudicators);
        await deployer.deploy(adjudicators);
        await deployer.link(adjudicators, plasmaCM);
        await deployer.link(state, plasmaCM);
        await deployer.deploy(plasmaCM);
      });
    });
  });
};
