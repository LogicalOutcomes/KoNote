# This module handles all logic related user accounts.
#
# See also: persist/session

Async = require 'async'
Fs = require 'fs'
Path = require 'path'

{SymmetricEncryptionKey} = require './crypto'

userNameRegex = /^[a-zA-Z0-9_-]+$/

# TODO
# - readAccount: requires creds
# - createAccount: requires admin priv
# - changeAccountPassword: requires admin priv and password (maybe add recovery feature?)
# - changeAccountType: requires admin priv
# - deleteAccount: requires admin priv

getUserDir = (dataDir, userName) ->
	unless userNameRegex.exec userName
		throw new Error "invalid characters in user name"

	return Path.join 'data', 'users', userName

# Read a user's private account data
readAccount = (dataDir, userName, password, cb) ->
	userDir = getUserDir dataDir, userName
	authParams = null
	userEncryptionKey = null
	privKeyFile = null
	accountType = null

	Async.series [
		(cb) ->
			Fs.readFile Path.join(userDir, 'auth-params'), (err, buf) ->
				if err
					if err.code is 'ENOENT'
						cb new UnknownUserNameError()
						return

					cb err
					return

				authParams = JSON.parse buf
				cb()
		(cb) ->
			SymmetricEncryptionKey.derive password, authParams, (err, result) ->
				if err
					cb err
					return

				userEncryptionKey = result
				cb()
		(cb) ->
			Fs.readFile Path.join(userDir, 'private-keys'), (err, buf) ->
				if err
					cb err
					return

				try
					decryptedJson = userEncryptionKey.decrypt buf
				catch err
					# If decryption fails, we're probably using the wrong key
					cb new IncorrectPasswordError()
					return

				privKeyFile = JSON.parse decryptedJson
				cb()
		(cb) ->
			Fs.readFile Path.join(userDir, 'account-type'), {encoding: 'utf8'}, (err, result) ->
				if err
					cb err
					return

				accountType = result
				cb()
	], (err) ->
		if err
			cb err
			return

		userEncryptionKey.erase()

		globalEncryptionKey = SymmetricEncryptionKey.import privKeyFile.globalEncryptionKey
		cb null, {userName, accountType, globalEncryptionKey}

class UnknownUserNameError extends Error
	constructor: ->
		super

class IncorrectPasswordError extends Error
	constructor: ->
		super

module.exports = {readAccount, UnknownUserNameError, IncorrectPasswordError}
