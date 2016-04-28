var $ = require('jquery');
var Fs = require('fs')

var Config = {};

// Ordered sequence of configuration overrides
var configFileNames = ['default', 'customer', 'production', 'develop']

// Loop over config files to build master config exports
$.each(configFileNames, function (index, fileName) {
	try {
		var configType = require('./'+fileName+'.json');
		$.extend(true, Config, configType);
	}
	catch (err) {
		if (err.code !== 'MODULE_NOT_FOUND') {
			throw new Error(err);
		}
	}
});

// Read src version from package.json
Config.version = JSON.parse(Fs.readFileSync('./package.json')).version;

module.exports = Config;