(function () {
	var Stylus = require('stylus');
	var Fs = require('fs');

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
		throw "Unmatched NW Versions: [package.json: "+ nwPackage + "] [installed: " + nwRunning + "]"
	}

	// In order to avoid the need for Grunt or a similar build system,
	// we'll compile the Stylus code at runtime.
	var mainStylusCode = Fs.readFileSync('main.styl', {encoding: 'utf-8'});
	var stylusOpts = {filename: 'main.styl', sourcemap: {inline: true}};
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
	});
})();
