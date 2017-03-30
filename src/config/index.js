// Copyright (c) Konode. All rights reserved.
// This source code is subject to the terms of the Mozilla Public License, v. 2.0
// that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

// Merges config setting files (JSON) in order

var Imm = require('immutable');

var Config = Imm.Map();

// Ordered sequence of configuration overrides
var configFileNames = ['default', 'customer', 'production', 'develop'];

// Loop over config files to build master config exports
configFileNames.forEach(function (fileName) {
	try {
		var configType = require('./'+fileName+'.json');
		Config = Config.mergeDeepWith((prev, next) => {
			return next;
		}, Imm.fromJS(configType));
	} catch (err) {
		if (err.code !== 'MODULE_NOT_FOUND') {
			throw new Error(err);
		}
	}
});

module.exports = Config.toJS();
