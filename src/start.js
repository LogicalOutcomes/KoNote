// Copyright (c) Konode. All rights reserved.
// This source code is subject to the terms of the Mozilla Public License, v. 2.0 
// that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

(function () {
	console.time('initLoad')
	var Fs = require('fs');
	var Config = require('./config');

	console.time('checkVersion')

	// Ensure package.json NW dependancy and installed NW are the same version
	var pkg = JSON.parse(Fs.readFileSync('package.json', 'utf8'))
	var nwName;
	switch(pkg.scripts.start) {
		case "nodewebkit .": nwName = "nodewebkit"; break;
		case "nw .": nwName = "nw"; break;
		default: throw new Error("Unknown nwjs name found in package.json for scripts.start")
	}
	// Grabs nw version from package, removes things like ^> etc.
	var nwPackage = pkg.dependencies[nwName].replace(/[^0-9.]/g, "")
	var nwRunning = process.versions['node-webkit']	

	if (nwPackage !== nwRunning) {
		var errMsg = "Unmatched NW Versions: [package.json: "+ nwPackage + "] [installed: " + nwRunning + "]";
		console.error(errMsg);
		alert(errMsg);
		return;
	}

	console.timeEnd('checkVersion')

	// In order to avoid the need for Grunt or a similar build system,
	// we'll compile the Stylus code at runtime.
	if Config.devMode {
		console.time('compileStylus')
		var Stylus = require('stylus');
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

			console.timeEnd('compileStylus')

			console.time('injectCSS')
			// Inject the compiled CSS into the page
			window.document.getElementById('main-css').innerHTML = compiledCss;
			console.timeEnd('injectCSS')

			console.time('registerCoffeescriptCompiler')
			// Register the CoffeeScript compiler
			require('coffee-script/register');
			console.timeEnd('registerCoffeescriptCompiler')

			// Run the app
			console.time('initApp')
			require('./main').init(window);
			console.timeEnd('initApp')
		});
	} else {
		console.time('initApp')
		require('./main').init(window);
		console.timeEnd('initApp')
	}
})();
