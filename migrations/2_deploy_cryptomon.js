var CryptoMon = artifacts.require("CryptoMons");

module.exports = function(deployer) {
  deployer.deploy(CryptoMon, "0x0000000000000000000000000000000000000000");
};
