# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Provides access to persistent data storage.
# Any reading/writing of data should be done using this module.


{buildDataDirectory} = require './setup'
Lock = require './lock'
Session = require './session'
Users = require './users'
Utils = require './utils'

module.exports = {
	buildDataDirectory
	initializeCrypto: Utils.initializeCrypto
	generateId: Utils.generateId
	IOError: Utils.IOError
	ObjectNotFoundError: Utils.ObjectNotFoundError
	TimestampFormat: Utils.TimestampFormat
	Lock
	Session
	Users
}
