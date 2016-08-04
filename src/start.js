// Copyright (c) Konode. All rights reserved.
// This source code is subject to the terms of the Mozilla Public License, v. 2.0
// that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

(function () {

	var Config = require('./config');

	if (!Config.devMode) {
		/////////// PRODUCTION MODE ///////////
		process.env.NODE_ENV = 'production';

		require('./main').init(window);

		return;
	}

	/////////// DEVELOPMENT MODE ///////////
	process.env.NODE_ENV = 'development';

	// In order to avoid the need for Grunt or a similar build system,
	// we'll compile the Stylus code at runtime.
	var Stylus = require('stylus');
	var Fs = require('fs');

	var mainStylusCode = Fs.readFileSync('src/main.styl', {encoding: 'utf-8'});
	var stylusOpts = {filename: 'src/main.styl', sourcemap: {inline: true}};

	Stylus.render(mainStylusCode, stylusOpts, function (err, compiledCss) {
		if (err) {
			console.error(err);
			if (err.stack) {
				console.error(err.stack);
			}
			return;
		}

		// Inject the compiled CSS into the page
		window.document.getElementById('main-css').innerHTML = compiledCss;

		// Register the CoffeeScript compiler
		require('coffee-script/register');

		// Run the app
		require('./main').init(window);

		global.console.info("*** Developer Mode ***");

		return;
	});

})();
