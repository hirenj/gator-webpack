const vm = require('vm');
const fs = require('fs');
const path = require('path');
const m = require('module');

const config_data = fs.readFileSync(path.join(__dirname,'./webpack.config.js'));

function LoadConfig() {
  let retval = vm.runInThisContext(m.wrap(config_data))(exports,require,module,__filename,__dirname);
  return module.exports;
}

module.exports = LoadConfig;