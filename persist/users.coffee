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
				if accountType is 'admin' and global.ActiveSession.systemEncryptionKey?
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

	deactivate: (cb) =>
		publicInfo = null
		accountKeyFileNames = null

		Async.series [
			(cb) =>
				Fs.readFile Path.join(@_userDir, 'public-info'), (err, buf) =>
					if err
						cb err
						return

					publicInfo = JSON.parse buf

					unless publicInfo.isActive
						cb new DeactivatedAccountError()
						return

					cb()
			(cb) =>
				publicInfo.isActive = false

				Fs.writeFile Path.join(@_userDir, 'public-info'), JSON.stringify(publicInfo), cb
			(cb) =>
				Fs.readdir @_userDir, (err, fileNames) =>
					if err
						cb err
						return

					accountKeyFileNames = Imm.List(fileNames)
					.filter (fileName) =>
						return fileName.startsWith 'account-key-'

					cb()
			(cb) =>
				Async.each accountKeyFileNames, (fileName, cb) ->
					Fs.unlink Path.join(@_userDir, fileName), cb
				, cb
		], cb

	# Provides callback with boolean isPasswordValid
	checkPassword: (userPassword, cb) =>
		# Not all of decryptWithPassword is actually needed to check the
		# password.  If needed, this can be reimplemented to be more efficient.

		@decryptWithPassword userPassword, (err, result) =>
			if err
				if err instanceof IncorrectPasswordError
					cb null, false
					return

				cb err
				return

			cb true

	decryptWithPassword: (userPassword, cb) =>
		unless @publicInfo.isActive
			cb new DeactivatedAccountError()
			return

		userDir = @_userDir
		accountKeyId = null
		accountKeyInfo = null
		accountKey = null
		privateInfo = null
		accountType = null
		decryptedAccount = null

		Async.series [
			(cb) ->
				Fs.readdir userDir, (err, fileNames) ->
					if err
						if err.code is 'ENOENT'
							cb new UnknownUserNameError()
							return

						cb err
						return

					# Find the highest (i.e. most recent) account key ID
					accountKeyId = Imm.List(fileNames)
					.filter (fileName) ->
						return fileName.startsWith 'account-key-'
					.map (fileName) ->
						return Number(fileName['account-key-'.length...])
					.max()

					cb()
			(cb) ->
				Fs.readFile Path.join(userDir, "account-key-#{accountKeyId}"), (err, buf) ->
					if err
						cb err
						return

					accountKeyInfo = JSON.parse buf
					cb()
			(cb) ->
				SymmetricEncryptionKey.derive userPassword, accountKeyInfo.kdfParams, (err, result) ->
					if err
						cb err
						return

					pwEncryptionKey = result

					# Use password to decrypt account key
					encryptedAccountKey = Base64url.decode(accountKeyInfo.accountKey)
					try
						accountKey = SymmetricEncryptionKey.import(pwEncryptionKey.decrypt(encryptedAccountKey))
					catch err
						# If decryption fails, we're probably using the wrong key
						pwEncryptionKey.erase()
						cb new IncorrectPasswordError()
						return

					pwEncryptionKey.erase()

					cb()
			(cb) =>
				Fs.readFile Path.join(userDir, 'private-info'), (err, buf) ->
					if err
						cb err
						return

					privateInfo = JSON.parse accountKey.decrypt buf
					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, new DecryptedAccount(
				@dataDirectory, @userName,
				@publicInfo, privateInfo, accountKey,
				'privateaccess'
			)

	decryptWithSystemKey: (systemKey, cb) =>
		unless @publicInfo.isActive
			cb new DeactivatedAccountError()
			return

		userDir = @_userDir
		accountKey = null
		privateInfo = null
		accountType = null
		decryptedAccount = null

		Async.series [
			(cb) =>
				@_findMaxAccountKeyId (err, result) ->
					if err
						cb err
						return

					accountKeyId = result
					cb()
			(cb) ->
				Fs.readFile Path.join(userDir, "account-recovery"), (err, buf) ->
					if err
						if err.code is 'ENOENT'
							cb new UnknownUserNameError()
							return

						cb err
						return

					accountKey = SymmetricEncryptionKey.import systemKey.decrypt buf
					cb()
			(cb) =>
				Fs.readFile Path.join(userDir, 'private-info'), (err, buf) ->
					if err
						cb err
						return

					privateInfo = JSON.parse accountKey.decrypt buf
					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, new DecryptedAccount(
				@dataDirectory, @userName,
				@publicInfo, privateInfo, accountKey,
				'privateaccess'
			)

	_findMaxAccountKeyId: (cb) ->
		Fs.readdir @_userDir, (err, fileNames) ->
			if err
				if err.code is 'ENOENT'
					cb new UnknownUserNameError()
					return

				cb err
				return

			# Find the highest (i.e. most recent) account key ID
			accountKeyId = Imm.List(fileNames)
			.filter (fileName) ->
				return fileName.startsWith 'account-key-'
			.map (fileName) ->
				return Number(fileName['account-key-'.length...])
			.max()

			cb null, accountKeyId

class DecryptedAccount extends Account
	constructor: (@dataDirectory, @userName, @publicInfo, @privateInfo, @_accountKey, code) ->
		if code isnt 'privateaccess'
			# See Account.decrypt* instead
			throw new Error "DecryptedAccount constructor should only be used internally"

		@_userDir = getUserDir @dataDirectory, @userName

	setPassword: (newPassword, cb) ->
		kdfParams = generateKdfParams()
		nextAccountKeyId = null
		pwEncryptionKey = null

		Async.series [
			(cb) ->
				@_findMaxAccountKeyId (err, result) ->
					if err
						cb err
						return

					nextAccountKeyId = result + 1
					cb()
			(cb) ->
				SymmetricEncryptionKey.derive newPassword, kdfParams, (err, result) ->
					if err
						cb err
						return

					pwEncryptionKey = result
					cb()
			(cb) ->
				accountKeyEncoded = Base64url.encode pwEncryptionKey.encrypt(@_accountKey.export())
				data = {kdfParams, accountKey: accountKeyEncoded}

				Fs.writeFile Path.join(@_userDir, 'account-key-#{nextAccountKeyId}'), JSON.stringify(data), cb
		], cb

class UserNameTakenError extends CustomError
class UnknownUserNameError extends CustomError
class IncorrectPasswordError extends CustomError
class DeactivatedAccountError extends CustomError

module.exports = {
	isAccountSystemSetUp
	listAccounts
	readAccount
	Account
	DecryptedAccount
	UserNameTakenError
	UnknownUserNameError
	IncorrectPasswordError
	DeactivatedAccountError
}
