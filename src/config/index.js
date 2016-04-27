var $ = require('jquery');

module.exports = {};

// Ordered sequence of configuration overrides
var configFileNames = ['default', 'customer', 'production', 'develop']

// Loop over config files to build master config exports
$.each(configFileNames, function (index, fileName) {
	try {
		var config = require('./'+fileName+'.json');
		$.extend(true, module.exports, config);
	}
	catch (err) {
		if (err.code !== 'MODULE_NOT_FOUND') {
			throw err;
		}
	}
});