# Provides access to persistent data storage.
# Any reading/writing of data should be done using this module.

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
