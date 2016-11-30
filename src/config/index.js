var Fs = require('fs');
var Imm = require('immutable');

var Config = Imm.Map();

// Ordered sequence of configuration overrides
var configFileNames = ['default', 'customer', 'production', 'develop'];

// Loop over config files to build master config exports
configFileNames.forEach(function (fileName) {
	try {
		var configType = require('./'+fileName+'.json');
		Config = Config.mergeDeep(Imm.fromJS(configType));
	} catch (err) {
		if (err.code !== 'MODULE_NOT_FOUND') {
			throw new Error(err);
		}
	}
});

module.exports = Config.toJS();
