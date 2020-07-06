const CopyPlugin = require('copy-webpack-plugin');
const fs = require('fs');
const os = require('os');

const cp = require('child_process');
const path = require('path');

function run_npm(path,modules) {
  const result = cp.spawnSync( 'npm', ['install','--no-optional','--no-package-lock','--prefix' , path ].concat(modules), { shell: true });
  console.log(result.stdout.toString());
};

class ModuleInstaller {
  constructor(modules) {
    this.modules = modules;
  }
  // Define `apply` as its prototype method which is supplied with compiler as its argument
  apply(compiler) {
    const target_dir = fs.mkdtempSync(path.join(os.tmpdir(), 'module_installer-'));
    run_npm(target_dir,this.modules);
    Object.keys(compiler.options.entry).forEach(entryName => {
      compiler.options.plugins.push(
        new CopyPlugin({
          patterns: [{
            from: path.join(target_dir,'node_modules'),
            to: `js/${entryName}/node_modules` }]
          })
        );
    });
  }
}

module.exports = ModuleInstaller;