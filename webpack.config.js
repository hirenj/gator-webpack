
const fs = require('fs');
const path = require('path');
const ZipPlugin = require('zip-webpack-plugin');
const CopyPlugin = require('copy-webpack-plugin');

const GitRevisionPlugin = require('git-revision-webpack-plugin')
const gitRevisionPlugin = new GitRevisionPlugin({
      versionCommand: 'describe --always --tags --dirty'
    });

const RemovePlugin = require('remove-files-webpack-plugin');

function getEntries() {
  return fs.readdirSync('./lambdas/')
      .filter(
          (file) => file.match(/.*\.js$/)
      )
      .map((file) => {
          return {
              name: file.substring(0, file.length - 3),
              path: './lambdas/' + file
          }
      }).reduce((memo, file) => {
          memo[file.name] = file.path
          return memo;
      }, {})
}

const configBase = {
  target: 'node',
  entry: getEntries(),
  mode: 'production',
  output: {
    libraryTarget: "commonjs",
    filename: 'js/[name]/index.js'
  },
  optimization: {
    minimize: false,
  },
  externals:[
    { "aws-sdk": "commonjs aws-sdk" },
    { "../resources.conf.json": "./resources.conf.json" },
    { "./resources.conf.json": "./resources.conf.json" }

  ],
  devtool: 'inline-cheap-module-source-map',
  plugins: [
    new RemovePlugin({ after: {
        include: [path.resolve('dist/js')],
        log: true,
    } })
  ]
};


const configPlugins = {
    plugins: 
    Object.keys(configBase.entry).map((entryName) => {
        return [
        new CopyPlugin({patterns: [{ from: 'resources.conf.json', to: `js/${entryName}/resources.conf.json` }] }),
        new ZipPlugin({
            filename: `${entryName}-${gitRevisionPlugin.version()}`,
            include: [new RegExp(`${entryName}/.*`)],
            pathMapper: assetPath => assetPath.indexOf('node_modules') >= 0 ? assetPath.replace(/.*node_modules/,'node_modules') : path.basename(assetPath),
            extension: 'zip'
        })
        ]
    }).flat()
};
configBase.plugins = configBase.plugins.concat(configPlugins.plugins);

const config = Object.assign({}, configBase);


module.exports = config