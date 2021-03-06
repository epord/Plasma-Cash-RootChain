var CryptoMon = artifacts.require("CryptoMons");
var RootChain = artifacts.require("RootChain");
var ValidatorManagerContract = artifacts.require("ValidatorManagerContract");
var plasmaCM = artifacts.require("PlasmaCM");
var adjudicators = artifacts.require("Adjudicators");
var state = artifacts.require("State");
var BattleDamageCalculator = artifacts.require("BattleDamageCalculator");
var CMBTransition = artifacts.require("CMBTransition");
var CryptoMonBattles = artifacts.require("CryptoMonBattles");

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
        await deployer.deploy(plasmaCM, RootChain.address);
        await deployer.deploy(BattleDamageCalculator);
        await deployer.link(BattleDamageCalculator, CryptoMonBattles);
        await deployer.link(BattleDamageCalculator, CMBTransition);
        await deployer.deploy(CMBTransition);
        await deployer.link(CMBTransition, CryptoMonBattles);
        await deployer.deploy(CryptoMonBattles, RootChain.address, CryptoMon.address);
      });
    });
  });
};
