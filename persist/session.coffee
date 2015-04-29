# This module handles all logic related to login sessions, including logging
# in, logging out, and managing encryption keys.

Async = require 'async'
Fs = require 'fs'
Path = require 'path'

{SymmetricEncryptionKey} = require './crypto'

usersDirPath = Path.join 'data', 'users'

userNameRegex = /^[a-zA-Z0-9_-]+$/

login = (dataDir, userName, password, cb) ->
	unless userNameRegex.exec userName
		throw new Error "invalid characters in user name"

	userDir = Path.join dataDir, 'users', userName
	authParams = null
	userSymmKey = null
	privKeyFile = null

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

				userSymmKey = result
				cb()
		(cb) ->
			Fs.readFile Path.join(userDir, 'private-keys'), (err, buf) ->
				if err
					cb err
					return

				try
					decryptedJson = userSymmKey.decrypt buf
				catch err
					# If decryption fails, we're probably using the wrong key
					cb new IncorrectPasswordError()
					return

				privKeyFile = JSON.parse decryptedJson
				cb()
	], (err) ->
		if err
			cb err
			return

		cb null, new Session(userName, privKeyFile.globalEncryptionKey)

class Session
	constructor: (@_userName, @_globalEncryptionKey) ->
		@_ended = false
	logout: ->
		if @_ended
			throw new Error "session has already ended"

		@_ended = true
		@_globalEncryptionKey.erase()

class UnknownUserNameError extends Error
	constructor: ->
		super

class IncorrectPasswordError extends Error
	constructor: ->
		super

module.exports = {login, UnknownUserNameError, IncorrectPasswordError}
