// Copyright (c) Konode. All rights reserved.
// This source code is subject to the terms of the Mozilla Public License, v. 2.0
// that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

(function () {
    var Config = require('./config');
    chrome.privacy.services.passwordSavingEnabled.set({ value: false });
    chrome.privacy.services.spellingServiceEnabled.set({ value: false });
    chrome.settingsPrivate.setPref('spellcheck.dictionaries', [Config.language], "null", function() {console.log("language set!")});

})();
