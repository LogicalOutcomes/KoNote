# This module handles all logic related user accounts.
#
# See also: persist/session

Async = require 'async'
Fs = require 'fs'
Path = require 'path'

{
	generateSalt
	SymmetricEncryptionKey
} = require './crypto'

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

# Create a new user account
# User must have full file system access (i.e. be an admin)
createAccount = (dataDir, userName, password, accountType, cb) ->
	unless accountType in ['normal', 'admin']
		cb new Error "unknown account type #{JSON.stringify accountType}"
		return

	userName = userName.toLowerCase()

	userDir = getUserDir dataDir, userName
	authParams = {
		salt: generateSalt()
		iterationCount: 600000 # higher is more secure, but slower
	}
	userEncryptionKey = null

	Async.series [
		(cb) ->
			Fs.mkdir userDir, (err) ->
				if err
					if err.code is 'EEXIST'
						cb new UserNameTakenError()
						return

					cb err
					return

				cb()
		(cb) ->
			SymmetricEncryptionKey.derive password, authParams, (err, result) ->
				if err
					cb err
					return

				userEncryptionKey = result
				cb()
		(cb) ->
			authParamsPath = Path.join(userDir, 'auth-params')

			Fs.writeFile authParamsPath, JSON.stringify(authParams), cb
		(cb) ->
			accountTypePath = Path.join(userDir, 'account-type')

			Fs.writeFile accountTypePath, JSON.stringify(accountType), cb
		(cb) ->
			privateKeysPath = Path.join(userDir, 'private-keys')

			privateKeys = {
				globalEncryptionKey: global.ActiveSession.globalEncryptionKey.export()
			}
			encryptedData = userEncryptionKey.encrypt JSON.stringify privateKeys

			Fs.writeFile privateKeysPath, encryptedData, cb
	], (err) ->
		if err
			cb err
			return

		cb()

# Read a user's private account data
readAccount = (dataDir, userName, password, cb) ->
	userName = userName.toLowerCase()

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

				accountType = JSON.parse result
				cb()
	], (err) ->
		if err
			cb err
			return

		userEncryptionKey.erase()

		globalEncryptionKey = SymmetricEncryptionKey.import privKeyFile.globalEncryptionKey
		cb null, {userName, accountType, globalEncryptionKey}

class UserNameTakenError extends Error
	constructor: ->
		super

class UnknownUserNameError extends Error
	constructor: ->
		super

class IncorrectPasswordError extends Error
	constructor: ->
		super

module.exports = {
	createAccount
	readAccount
	UserNameTakenError
	UnknownUserNameError
	IncorrectPasswordError
}
