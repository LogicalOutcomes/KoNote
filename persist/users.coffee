# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module handles all logic related to user accounts.
#
# See also: persist/session
#
# TODO Make operations atomic
# TODO Find a better way of getting data dir location

Async = require 'async'
Base64url = require 'base64url'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'

{
	generateSalt
	SymmetricEncryptionKey
} = require './crypto'

{CustomError} = require './utils'

userNameRegex = /^[a-zA-Z0-9_-]+$/

generateKdfParams = ->
	return {
		salt: generateSalt()
		iterationCount: 600000 # higher is more secure, but slower
	}

getUserDir = (dataDir, userName) ->
	unless userNameRegex.exec userName
		throw new Error "invalid characters in user name"

	return Path.join dataDir, '_users', userName

# Check if there are any user accounts set up
isAccountSystemSetUp = (dataDir, cb) ->
	Fs.readdir Path.join(dataDir, '_users'), (err, subdirs) ->
		if err
			if err.code is 'ENOENT'
				cb null, false
				return

			cb err
			return

		userNames = Imm.List(subdirs)
		.filter (dirName) ->
			return userNameRegex.exec(dirName)

		cb null, (userNames.size > 0)

# TODO rename to listUserNames
listAccounts = (dataDir, cb) ->
	Fs.readdir Path.join(dataDir, '_users'), (err, subdirs) ->
		if err
			cb err
			return

		userNames = Imm.List(subdirs)
		.filter (dirName) ->
			return userNameRegex.exec(dirName)

		cb null, userNames

class Account
	constructor: (@dataDirectory, @userName, @publicInfo, code) ->
		if code isnt 'privateaccess'
			# See Account.read instead
			throw new Error "Account constructor should only be used internally"

		@_userDir = getUserDir @dataDirectory, @userName

	@create: (dataDir, userName, password, accountType, cb) ->
		unless accountType in ['normal', 'admin']
			cb new Error "unknown account type #{JSON.stringify accountType}"
			return

		userName = userName.toLowerCase()

		userDir = getUserDir dataDir, userName

		publicInfo = {accountType, isActive: true}
		kdfParams = generateKdfParams()
		accountEncryptionKey = SymmetricEncryptionKey.generate()

		pwEncryptionKey = null

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
				SymmetricEncryptionKey.derive password, kdfParams, (err, result) ->
					if err
						cb err
						return

					pwEncryptionKey = result
					cb()
			(cb) ->
				publicInfoPath = Path.join(userDir, 'public-info')

				Fs.writeFile publicInfoPath, JSON.stringify(publicInfo), cb
			(cb) ->
				accountKeyFilePath = Path.join(userDir, 'account-key-1')

				# Encrypt account key with user's password
				encryptedAccountKey = pwEncryptionKey.encrypt accountEncryptionKey.export()

				accountKeyData = {
					kdfParams
					accountKey: Base64url.encode encryptedAccountKey
				}

				Fs.writeFile accountKeyFilePath, JSON.stringify(accountKeyData), cb
			(cb) ->
				accountRecoveryPath = Path.join(userDir, 'account-recovery')

				# Encrypt account key with system key to allow admins to reset
				# TODO get the system key in a better way
				# TODO first time set up
				encryptedAccountKey = global.ActiveSession.systemEncryptionKey.encrypt accountEncryptionKey.export()

				Fs.writeFile accountRecoveryPath, encryptedAccountKey, cb
			(cb) ->
				privateInfoPath = Path.join(userDir, 'private-info')

				if global.ActiveSession?
					globalEncryptionKey = global.ActiveSession.globalEncryptionKey
				else
					console.log """
						First time set up of new KoNote instance.  Generating encryption key.
					"""
					globalEncryptionKey = SymmetricEncryptionKey.generate()

				privateInfo = {
					globalEncryptionKey: globalEncryptionKey.export()
				}

				# TODO pass this in as an argument somehow
				if global.ActiveSession.systemEncryptionKey?
					privateInfo.systemEncryptionKey = global.ActiveSession.systemEncryptionKey

				encryptedData = accountEncryptionKey.encrypt JSON.stringify privateInfo

				Fs.writeFile privateInfoPath, encryptedData, cb
		], (err) ->
			if err
				cb err
				return

			cb null, new Account dataDir, userName, publicInfo, 'privateaccess'

	@read: (dataDir, userName, cb) =>
		userName = userName.toLowerCase()

		userDir = getUserDir dataDir, userName

		publicInfo = null

		Async.series [
			(cb) ->
				Fs.readFile Path.join(userDir, 'public-info'), (err, buf) ->
					if err
						if err.code is 'ENOENT'
							cb new UnknownUserNameError()
							return

						cb err
						return

					publicInfo = JSON.parse buf
					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, new Account dataDir, userName, publicInfo, 'privateaccess'

	decryptWithPassword: (userPassword, cb) =>
		userDir = @_userDir
		kdfParams = null
		pwEncryptionKey = null
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

					kdfParams = JSON.parse buf

					if kdfParams.isDeactivated
						cb new DeactivatedAccountError()
						return

					cb()
			(cb) ->
				SymmetricEncryptionKey.derive password, kdfParams, (err, result) ->
					if err
						cb err
						return

					pwEncryptionKey = result
					cb()
			(cb) ->
				Fs.readFile Path.join(userDir, 'private-keys'), (err, buf) ->
					if err
						cb err
						return

					try
						decryptedJson = pwEncryptionKey.decrypt buf
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

			pwEncryptionKey.erase()

			globalEncryptionKey = SymmetricEncryptionKey.import privKeyFile.globalEncryptionKey
			cb null, {userName, accountType, globalEncryptionKey}

resetAccountPassword = (dataDir, userName, newPassword, cb) ->
	userName = userName.toLowerCase()

	userDir = getUserDir dataDir, userName
	kdfParamsPath = Path.join(userDir, 'auth-params')

	newAuthParams = generateKdfParams()
	pwEncryptionKey = null

	Async.series [
		(cb) ->
			Fs.readFile kdfParamsPath, (err, buf) ->
				if err
					if err.code is 'ENOENT'
						cb new UnknownUserNameError()
						return

					cb err
					return

				oldAuthParams = JSON.parse buf

				if oldAuthParams.isDeactivated
					cb new DeactivatedAccountError()
					return

				cb()
		(cb) ->
			Fs.writeFile kdfParamsPath, JSON.stringify(newAuthParams), (err, buf) ->
				if err
					if err.code is 'ENOENT'
						cb new UnknownUserNameError()
						return

					cb err
					return

				cb()
		(cb) ->
			SymmetricEncryptionKey.derive newPassword, newAuthParams, (err, result) ->
				if err
					cb err
					return

				pwEncryptionKey = result
				cb()
		(cb) ->
			privateKeysPath = Path.join(userDir, 'private-keys')

			privateKeys = {
				globalEncryptionKey: global.ActiveSession.globalEncryptionKey.export()
			}
			encryptedData = pwEncryptionKey.encrypt JSON.stringify privateKeys

			Fs.writeFile privateKeysPath, encryptedData, cb
	], cb

deactivateAccount = (dataDir, userName, cb) ->
	userName = userName.toLowerCase()

	userDir = getUserDir dataDir, userName
	kdfParamsPath = Path.join(userDir, 'auth-params')

	kdfParams = {isDeactivated: true}

	Async.series [
		(cb) ->
			Fs.readFile kdfParamsPath, (err, buf) ->
				if err
					if err.code is 'ENOENT'
						cb new UnknownUserNameError()
						return

					cb err
					return

				oldAuthParams = JSON.parse buf

				if oldAuthParams.isDeactivated
					cb new DeactivatedAccountError()
					return

				cb()
		(cb) ->
			Fs.writeFile kdfParamsPath, JSON.stringify(kdfParams), (err, buf) ->
				if err
					if err.code is 'ENOENT'
						cb new UnknownUserNameError()
						return

					cb err
					return

				cb()
		(cb) ->
			privateKeysPath = Path.join(userDir, 'private-keys')

			Fs.unlink privateKeysPath, cb
	], cb

class UserNameTakenError extends CustomError
class UnknownUserNameError extends CustomError
class IncorrectPasswordError extends CustomError
class DeactivatedAccountError extends CustomError

module.exports = {
	isAccountSystemSetUp
	createAccount
	listAccounts
	readAccount
	resetAccountPassword
	deactivateAccount
	UserNameTakenError
	UnknownUserNameError
	IncorrectPasswordError
	DeactivatedAccountError
}
