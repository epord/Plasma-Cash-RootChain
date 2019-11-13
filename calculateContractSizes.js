const run = () => {
  const contractFolder = 'build/contracts';
  const fs = require('fs');

  fs.readdir(contractFolder, (err, files) => {
    files.forEach(file => {
      let contract = require("./" + contractFolder + "/" + file);
      console.log(file + "\t" + contract.deployedBytecode.length / 1000)
      if(contract.deployedBytecode.length / 1000 > 24) {
        console.log("^-----------------------------^")
      }
    });
  });
}

module.exports = run;