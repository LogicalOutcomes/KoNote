// Copyright (c) Konode. All rights reserved.
// This source code is subject to the terms of the Mozilla Public License, v. 2.0 
// that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

(function () {
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
		var errMsg = "Unmatched NW Versions: [package.json: "+ nwPackage + "] [installed: " + nwRunning + "]";
		console.error(errMsg);
		alert(errMsg);
		return;
	}

	// Run the app
	require('./main').init(window);
})();
