String.prototype.padding = function(n, c) {
  var val = this.valueOf();
  if ( Math.abs(n) <= val.length ) {
    return val;
  }
  var m = Math.max((Math.abs(n) - this.length) || 0, 0);
  var pad = Array(m + 1).join(String(c || ' ').charAt(0));
//      var pad = String(c || ' ').charAt(0).repeat(Math.abs(n) - this.length);
  return (n < 0) ? pad + val : val + pad;
//      return (n < 0) ? val + pad : pad + val;
};

const run = () => {
  const contractFolder = 'build/contracts';
  const fs = require('fs');
  fs.readdir(contractFolder, (err, files) => {
    files.map(file => require("./" + contractFolder + "/" + file))
      .sort((c1, c2) => c2.deployedBytecode.length -  c1.deployedBytecode.length)
      .forEach(contract => {
      console.log(contract.contractName.padding(25, "-") + contract.deployedBytecode.length / 2000)
      if(contract.deployedBytecode.length / 2000 > 24) {
        console.log("^-----------------------------^")
      }
    });
  });
}

module.exports = run;