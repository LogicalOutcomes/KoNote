# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module handles all logic related user accounts.
#
# See also: persist/session
#
# TODO Make operations atomic
# TODO Find a better way of getting data dir location

Async = require 'async'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'

{
	generateSalt
	SymmetricEncryptionKey
} = require './crypto'

{CustomError} = require './utils'

userNameRegex = /^[a-zA-Z0-9_-]+$/

generateUserAuthParams = ->
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

# Create a new user account
# User must have full file system access (i.e. be an admin)
createAccount = (dataDir, userName, password, accountType, cb) ->
	unless accountType in ['normal', 'admin']
		cb new Error "unknown account type #{JSON.stringify accountType}"
		return

	userName = userName.toLowerCase()

	userDir = getUserDir dataDir, userName
	authParams = generateUserAuthParams()
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

			if global.ActiveSession?
				globalEncryptionKey = global.ActiveSession.globalEncryptionKey
			else
				console.log """
					First time set up of new KoNote instance.  Generating encryption key.
				"""
				globalEncryptionKey = SymmetricEncryptionKey.generate()

			privateKeys = {
				globalEncryptionKey: globalEncryptionKey.export()
			}
			encryptedData = userEncryptionKey.encrypt JSON.stringify privateKeys

			Fs.writeFile privateKeysPath, encryptedData, cb
	], (err) ->
		if err
			cb err
			return

		cb()

listAccounts = (dataDir, cb) ->
	Fs.readdir Path.join(dataDir, '_users'), (err, subdirs) ->
		if err
			cb err
			return

		userNames = Imm.List(subdirs)
		.filter (dirName) ->
			return userNameRegex.exec(dirName)

		cb null, userNames

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

				if authParams.isDeactivated
					cb new DeactivatedAccountError()
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

resetAccountPassword = (dataDir, userName, newPassword, cb) ->
	userName = userName.toLowerCase()

	userDir = getUserDir dataDir, userName
	authParamsPath = Path.join(userDir, 'auth-params')

	newAuthParams = generateUserAuthParams()
	userEncryptionKey = null

	Async.series [
		(cb) ->
			Fs.readFile authParamsPath, (err, buf) ->
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
			Fs.writeFile authParamsPath, JSON.stringify(newAuthParams), (err, buf) ->
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

				userEncryptionKey = result
				cb()
		(cb) ->
			privateKeysPath = Path.join(userDir, 'private-keys')

			privateKeys = {
				globalEncryptionKey: global.ActiveSession.globalEncryptionKey.export()
			}
			encryptedData = userEncryptionKey.encrypt JSON.stringify privateKeys

			Fs.writeFile privateKeysPath, encryptedData, cb
	], cb

deactivateAccount = (dataDir, userName, cb) ->
	userName = userName.toLowerCase()

	userDir = getUserDir dataDir, userName
	authParamsPath = Path.join(userDir, 'auth-params')

	authParams = {isDeactivated: true}

	Async.series [
		(cb) ->
			Fs.readFile authParamsPath, (err, buf) ->
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
			Fs.writeFile authParamsPath, JSON.stringify(authParams), (err, buf) ->
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
