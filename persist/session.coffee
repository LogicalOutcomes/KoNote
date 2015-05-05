# This module handles all logic related to login sessions, including logging
# in, logging out, and managing encryption keys.

Async = require 'async'
Fs = require 'fs'
Path = require 'path'

{SymmetricEncryptionKey} = require './crypto'
Users = require './users'

login = (dataDir, userName, password, cb) ->
	Users.readAccount dataDir, userName, password, (err, account) ->
		if err
			cb err
			return

		cb null, new Session(
			account.userName
			account.accountType
			account.globalEncryptionKey
		)

class Session
	constructor: (@userName, @accountType, @globalEncryptionKey) ->
		unless @globalEncryptionKey instanceof SymmetricEncryptionKey
			throw new Error "invalid globalEncryptionKey"

		unless @accountType in ['normal', 'admin']
			throw new Error "unknown account type: #{JSON.stringify @_accountType}"

		@_ended = false
	isAdmin: ->
		return @accountType is 'admin'
	logout: ->
		if @_ended
			throw new Error "session has already ended"

		@_ended = true
		@globalEncryptionKey.erase()

module.exports = {
	login
	UnknownUserNameError: Users.UnknownUserNameError
	IncorrectPasswordError: Users.IncorrectPasswordError
}
