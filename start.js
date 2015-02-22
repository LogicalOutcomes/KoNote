(function () {
	var Stylus = require('stylus');
	var Fs = require('fs');

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
