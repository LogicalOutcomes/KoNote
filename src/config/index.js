var configCustomer, configDev, err;
var _ = require('underscore');

module.exports = {};

try {
	configDefault = require('./default.json');
	_.extend(module.exports, configDefault);
} catch (_error) {
	err = _error;
	if (err.code !== 'MODULE_NOT_FOUND') {
		throw err;
	}
}

try {
	configCustomer = require('./customer.json');
	_.extend(module.exports, configCustomer);
} catch (_error) {
	err = _error;
	if (err.code !== 'MODULE_NOT_FOUND') {
		throw err;
	}
}

try {
	configProduction = require('./production.json');
	_.extend(module.exports, configProduction);
} catch (_error) {
	err = _error;
	if (err.code !== 'MODULE_NOT_FOUND') {
		throw err;
	}
}

try {
	configDev = require('./develop.json');
	_.extend(module.exports, configDev);
} catch (_error) {
	err = _error;
	if (err.code !== 'MODULE_NOT_FOUND') {
		throw err;
	}
}
