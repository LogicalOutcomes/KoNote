# Provides access to persistent data storage.
# Any reading/writing of data should be done using this module.
#
# The persistence module provides several features beyond working directly with files:
#  - Locking (coming soon): provides a mechanism for preventing other users from accessing a
#  file while it is in use.
#  - Schemas: all data objects are validated to ensure that they are structured
#  properly and don't contain any unexpected fields.  This is important for
#  catching bugs early (since JS uses dynamic typing).
#  - Revision histories (coming soon)
#  - Cryptographic verification of authorship (coming soon)
#  - Cryptographic verification of timestamps (coming soon)
#  - Caching (coming soon?)

Imm = require 'immutable'

DataModels = require './dataModels'
Lock = require './lock'
Session = require './session'
Users = require './users'
Utils = require './utils'

module.exports = {
	generateId: Utils.generateId
	setUpDataDirectory: DataModels.setUpDataDirectory
	IOError: Utils.IOError
	ObjectNotFoundError: Utils.ObjectNotFoundError
	TimestampFormat: Utils.TimestampFormat
	Lock
	Session
	Users
}
