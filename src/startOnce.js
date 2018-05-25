// Copyright (c) Konode. All rights reserved.
// This source code is subject to the terms of the Mozilla Public License, v. 2.0
// that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

(function () {
    var Config = require('./config');

    chrome.privacy.services.passwordSavingEnabled.set({ value: false });
    chrome.privacy.services.spellingServiceEnabled.set({ value: false });
    chrome.settingsPrivate.setPref('spellcheck.dictionaries', [Config.language], "null", function() {console.log("language set!")});

	if (Config.devMode) {
        process.env.NODE_ENV = 'development';
        global.console.info("*** Developer Mode ***");
	} else {
        process.env.NODE_ENV = 'production';
	}

})();
