# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module handles all logic related to user accounts.
#
# See also: persist/session
#
# TODO Make operations atomic
# TODO Find a better way of getting data dir location

Assert = require 'assert'
Async = require 'async'
Base64url = require 'base64url'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'

{
	generateSalt
	SymmetricEncryptionKey
	PrivateKey
	PublicKey
} = require './crypto'

{CustomError} = require './utils'

userNameRegex = /^[a-zA-Z0-9_-]+$/

# Check if the account system is set up.  The account system must be set up
# before any accounts can be created, see `Account.setUp`.
#
# Errors:
# - IOError
#
# (string dataDir, function cb(Error err, boolean isSetUp)) -> undefined
isAccountSystemSetUp = (dataDir, cb) ->
	Fs.readdir Path.join(dataDir, '_users'), (err, subdirs) ->
		if err
			if err.code is 'ENOENT'
				cb null, false
				return

			cb new IOError err
			return

		userNames = Imm.List(subdirs)
		.filter (dirName) ->
			return userNameRegex.exec(dirName)

		cb null, (userNames.size > 0)

# Produce a list of the user names of all accounts in the system.
#
# Errors:
# - IOError
#
# (string dataDir, function cb(Error err, Imm.List userNames)) -> undefined
listUserNames = (dataDir, cb) ->
	Fs.readdir Path.join(dataDir, '_users'), (err, subdirs) ->
		if err
			cb new IOError err
			return

		userNames = Imm.List(subdirs)
		.filter (dirName) ->
			return dirName isnt '_system'
		.filter (dirName) ->
			return userNameRegex.exec(dirName)

		cb null, userNames

# Account objects contain the public information on a user account (and related operations).
# Account objects also provide "decrypt" methods that are gateways to the
# private information in a user account (see DecryptedAccount).
class Account
	# Private constructor
	constructor: (@dataDirectory, @userName, @publicInfo, code) ->
		if code isnt 'privateaccess'
			# See Account.read instead
			throw new Error "Account constructor should only be used internally"

		@_userDir = getUserDir @dataDirectory, @userName

	# Sets up the account system.  A new data directory must be set up before
	# any user accounts can be created.  This set up process generates a
	# special "_system" account which can be used to set up other accounts.
	# The _system account does not have a password, and cannot be accessed from
	# the UI.  It exists just for the purpose of setting up the first admin
	# account.
	#
	# Note: this method assumes that the data directory has already undergone
	# some basic set up outside of the account system (see
	# `Persist.setUpDataDirectory`).
	#
	# Errors:
	# - IOError
	#
	# (string dataDir, function cb(Error err, Account systemAccount)) -> undefined
	@setUp: (dataDir, cb) ->
		# Create a mock "_system" user just for creating the first real accounts
		publicInfo = {
			accountType: 'admin'
			isActive: true
		}
		privateInfo = {
			globalEncryptionKey: SymmetricEncryptionKey.generate().export()
			systemPrivateKey: null
		}
		systemPublicKey = null

		Async.series [
			(cb) =>
				PrivateKey.generate (err, result) =>
					if err
						cb err
						return

					privateInfo.systemPrivateKey = result.export()
					systemPublicKey = result.getPublicKey().export()
					cb()
			(cb) =>
				Fs.mkdir Path.join(dataDir, '_users', '_system'), (err) =>
					if err
						cb new IOError err
						return

					cb()
			(cb) =>
				Fs.writeFile Path.join(dataDir, '_users', '_system', 'public-key'), systemPublicKey, (err) =>
					if err
						cb new IOError err
						return

					cb()
		], (err) =>
			if err
				cb err
				return

			systemAccount = new DecryptedAccount(dataDir, '_system', publicInfo, privateInfo, null, 'privateaccess')
			cb null, systemAccount

	# Creates a new user account, and returns an Account object representing
	# that account.
	#
	# Errors:
	# - UserNameTakenError if the user name has already been taken
	# - IOError
	#
	# (DecryptedAccount loggedInAccount, string userName, string password, string accountType,
	#  function cb(Error err, Account newAccount)) -> undefined
	@create: (loggedInAccount, userName, password, accountType, cb) ->
		unless accountType in ['normal', 'admin']
			cb new Error "unknown account type #{JSON.stringify accountType}"
			return

		if accountType is 'admin'
			Assert.strictEqual loggedInAccount.publicInfo.accountType, 'admin', 'only admins can create admins'

		userName = userName.toLowerCase()

		userDir = getUserDir loggedInAccount.dataDirectory, userName

		publicInfo = {accountType, isActive: true}
		kdfParams = generateKdfParams()
		accountEncryptionKey = SymmetricEncryptionKey.generate()

		systemPublicKey = null
		pwEncryptionKey = null
		encryptedAccountKey = null

		Async.series [
			(cb) ->
				publicKeyPath = Path.join(loggedInAccount.dataDirectory, '_users', '_system', 'public-key')

				Fs.readFile publicKeyPath, (err, buf) ->
					if err
						cb new IOError err
						return

					systemPublicKey = PublicKey.import(buf.toString())
					cb()
			(cb) ->
				Fs.mkdir userDir, (err) ->
					if err
						if err.code is 'EEXIST'
							cb new UserNameTakenError()
							return

						cb new IOError err
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

				Fs.writeFile publicInfoPath, JSON.stringify(publicInfo), (err) =>
					if err
						cb new IOError err
						return

					cb()
			(cb) ->
				accountKeyFilePath = Path.join(userDir, 'account-key-1')

				# Encrypt account key with user's password
				encryptedAccountKey = pwEncryptionKey.encrypt accountEncryptionKey.export()

				accountKeyData = {
					kdfParams
					accountKey: Base64url.encode encryptedAccountKey
				}

				Fs.writeFile accountKeyFilePath, JSON.stringify(accountKeyData), (err) =>
					if err
						cb new IOError err
						return

					cb()
			(cb) ->
				# Encrypt account key with system key to allow admins to reset
				systemPublicKey.encrypt accountEncryptionKey.export(), (err, result) ->
					if err
						cb err
						return

					encryptedAccountKey = result
					cb()
			(cb) ->
				accountRecoveryPath = Path.join(userDir, 'account-recovery')

				Fs.writeFile accountRecoveryPath, encryptedAccountKey, (err) =>
					if err
						cb new IOError err
						return

					cb()
			(cb) ->
				privateInfoPath = Path.join(userDir, 'private-info')

				privateInfo = {
					globalEncryptionKey: loggedInAccount.privateInfo.globalEncryptionKey
				}

				if accountType is 'admin'
					Assert.strictEqual loggedInAccount.publicInfo.accountType, 'admin', 'only admins can create admins'

					privateInfo.systemPrivateKey = loggedInAccount.privateInfo.systemPrivateKey

				encryptedData = accountEncryptionKey.encrypt JSON.stringify privateInfo

				Fs.writeFile privateInfoPath, encryptedData, (err) =>
					if err
						cb new IOError err
						return

					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, new Account loggedInAccount.dataDirectory, userName, publicInfo, 'privateaccess'

	# Read the public information for the account with the specified user name.
	#
	# Errors:
	# - UnknownUserNameError if no account exists with that user name
	# - IOError
	#
	# (string dataDir, string userName, function cb(Error err, Account a)) -> undefined
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

						cb new IOError err
						return

					publicInfo = JSON.parse buf
					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, new Account dataDir, userName, publicInfo, 'privateaccess'

	# Deactivate this account.  Requires the ability to modify/delete files.
	#
	# Errors:
	# - DeactivatedAccountError if the account has already been deactivated
	# - IOError
	#
	# (function cb(Error err)) -> undefined
	deactivate: (cb) =>
		# BEGIN v1.3.1 migration
		if Fs.existsSync Path.join(@_userDir, 'auth-params')
			# This account is in the old format.  To save time, I didn't
			# implement this method.
			cb new Error "cannot deactivate accounts in old format"
			return
		# END v1.3.1 migration

		publicInfo = null
		accountKeyFileNames = null

		Async.series [
			(cb) =>
				Fs.readFile Path.join(@_userDir, 'public-info'), (err, buf) =>
					if err
						cb new IOError err
						return

					publicInfo = JSON.parse buf

					unless publicInfo.isActive
						cb new DeactivatedAccountError()
						return

					cb()
			(cb) =>
				publicInfo.isActive = false

				Fs.writeFile Path.join(@_userDir, 'public-info'), JSON.stringify(publicInfo), (err) =>
					if err
						cb new IOError err
						return

					cb()
			(cb) =>
				Fs.readdir @_userDir, (err, fileNames) =>
					if err
						cb new IOError err
						return

					accountKeyFileNames = Imm.List(fileNames)
					.filter (fileName) =>
						return fileName.startsWith 'account-key-'

					cb()
			(cb) =>
				Async.each accountKeyFileNames.toArray(), (fileName, cb) =>
					Fs.unlink Path.join(@_userDir, fileName), (err) =>
						if err
							cb new IOError err
							return

						cb()
				, cb
		], cb

	# Check if the specified password is valid for this user account.
	#
	# Errors:
	# - IncorrectPasswordError if the passsword was incorrect
	# - IOError
	#
	# (string userPassword, function cb(Error err)) -> undefined
	checkPassword: (userPassword, cb) =>
		# Not all of decryptWithPassword is actually needed to check the
		# password.  If needed, this can be reimplemented to be more efficient.

		@decryptWithPassword userPassword, (err, result) =>
			if err
				cb err
				return

			cb()

	# Access this account's private information using the specified password.
	#
	# Errors:
	# - DeactivatedAccountError
	# - UnknownUserNameError if this account no longer exists
	# - IncorrectPasswordError
	# - IOError
	#
	# (string userPassword, function cb(Error err, DecryptedAccount a)) -> undefined
	decryptWithPassword: (userPassword, cb) =>
		unless @publicInfo.isActive
			cb new DeactivatedAccountError()
			return

		# BEGIN v1.3.1 migration
		if Fs.existsSync Path.join(@_userDir, 'auth-params')
			# This account is in the old format.

			accountKey = SymmetricEncryptionKey.generate()
			systemUserDir = Path.join(@dataDirectory, '_users', '_system')

			oldKdfParams = null
			oldPwEncryptionKey = null
			globalEncryptionKey = null
			kdfParams = generateKdfParams()
			pwEncryptionKey = null
			systemPrivateKey = null
			systemPublicKey = null
			accountRecovery = null

			Async.series [
				(cb) =>
					Fs.readFile Path.join(@_userDir, 'auth-params'), (err, result) =>
						if err
							cb new IOError err
							return

						oldKdfParams = JSON.parse result
						cb()
				(cb) =>
					SymmetricEncryptionKey.derive userPassword, oldKdfParams, (err, result) =>
						if err
							cb err
							return

						oldPwEncryptionKey = result
						cb()
				(cb) =>
					Fs.readFile Path.join(@_userDir, 'private-keys'), (err, result) =>
						if err
							cb new IOError err
							return

						try
							oldPrivateKeys = JSON.parse oldPwEncryptionKey.decrypt result
						catch err
							console.error err.stack

							# If decryption fails, we're probably using the wrong key
							cb new IncorrectPasswordError()
							return

						globalEncryptionKey = SymmetricEncryptionKey.import oldPrivateKeys.globalEncryptionKey
						cb()
				(cb) =>
					Fs.readFile Path.join(systemUserDir, 'old-key'), (err, buf) =>
						if err
							cb new IOError err
							return

						systemPrivateKey = PrivateKey.import(globalEncryptionKey.decrypt(buf).toString())
						systemPublicKey = systemPrivateKey.getPublicKey()
						cb()
				(cb) =>
					SymmetricEncryptionKey.derive userPassword, kdfParams, (err, result) =>
						if err
							cb err
							return

						pwEncryptionKey = result
						cb()
				(cb) =>
					accountKeyFile = JSON.stringify {
						accountKey: Base64url.encode pwEncryptionKey.encrypt(accountKey.export())
						kdfParams
					}

					Fs.writeFile Path.join(@_userDir, 'account-key-1'), accountKeyFile, (err) =>
						if err
							cb new IOError err
							return

						cb()
				(cb) =>
					systemPublicKey.encrypt accountKey.export(), (err, result) =>
						if err
							cb err
							return

						accountRecovery = result
						cb()
				(cb) =>
					Fs.writeFile Path.join(@_userDir, 'account-recovery'), accountRecovery, (err) =>
						if err
							cb new IOError err
							return

						cb()
				(cb) =>
					privateInfo = {
						globalEncryptionKey: globalEncryptionKey.export()
					}

					if @publicInfo.accountType is 'admin'
						privateInfo.systemPrivateKey = systemPrivateKey.export()

					privateInfoEncrypted = accountKey.encrypt JSON.stringify(privateInfo)

					Fs.writeFile Path.join(@_userDir, 'private-info'), privateInfoEncrypted, (err) =>
						if err
							cb new IOError err
							return

						cb()
				(cb) =>
					Fs.unlink Path.join(@_userDir, 'private-keys'), (err) =>
						if err
							cb new IOError err
							return

						cb()
				(cb) =>
					Fs.unlink Path.join(@_userDir, 'auth-params'), (err) =>
						if err
							cb new IOError err
							return

						cb()
			], (err) =>
				if err
					cb err
					return

				# Restart -- this time it should be in the new format
				@decryptWithPassword userPassword, cb
			return
		# END v1.3.1 migration

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

						cb new IOError err
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
						cb new IOError err
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
					encryptedAccountKey = Base64url.toBuffer(accountKeyInfo.accountKey)
					try
						accountKeyBuf = pwEncryptionKey.decrypt(encryptedAccountKey)
					catch err
						console.error err.stack

						# If decryption fails, we're probably using the wrong key
						cb new IncorrectPasswordError()
						return

					accountKey = SymmetricEncryptionKey.import(accountKeyBuf.toString())

					cb()
			(cb) =>
				Fs.readFile Path.join(userDir, 'private-info'), (err, buf) ->
					if err
						cb new IOError err
						return

					privateInfo = JSON.parse accountKey.decrypt buf
					cb()
		], (err) =>
			if err
				cb err
				return

			cb null, new DecryptedAccount(
				@dataDirectory, @userName,
				@publicInfo, privateInfo, accountKey,
				'privateaccess'
			)

	# Access this account's private information using the system key (i.e. the
	# admin override).  `loggedInAccount` must be an admin account.
	#
	# Errors:
	# - DeactivatedAccountError
	# - UnknownUserNameError if this account no longer exists
	# - IOError
	#
	# (DecryptedAccount loggedInAccount, function cb(Error err, DecryptedAccount a)) -> undefined
	decryptWithSystemKey: (loggedInAccount, cb) =>
		unless @publicInfo.isActive
			cb new DeactivatedAccountError()
			return

		unless loggedInAccount.publicInfo.accountType is 'admin'
			cb new Error "only admins have access to the system key"
			return

		# BEGIN v1.3.1 migration
		if Fs.existsSync Path.join(@_userDir, 'auth-params')
			# This account is in the old format.

			privateInfo = {
				globalEncryptionKey: loggedInAccount.privateInfo.globalEncryptionKey
			}
			if @publicInfo.accountType is 'admin'
				privateInfo.systemPrivateKey = loggedInAccount.privateInfo.systemPrivateKey

			accountKey = SymmetricEncryptionKey.generate()

			cb null, new DecryptedAccount(
				@dataDirectory, @userName,
				@publicInfo, privateInfo, accountKey,
				'privateaccess'
			)
			return
		# END v1.3.1 migration

		userDir = @_userDir
		accountKey = null
		privateInfo = null
		accountType = null
		decryptedAccount = null
		accountRecovery = null

		Async.series [
			(cb) =>
				@_findMaxAccountKeyId (err, result) ->
					if err
						cb err
						return

					accountKeyId = result
					cb()
			(cb) =>
				Fs.readFile Path.join(userDir, "account-recovery"), (err, buf) ->
					if err
						if err.code is 'ENOENT'
							cb new UnknownUserNameError()
							return

						cb new IOError err
						return

					accountRecovery = buf
					cb()
			(cb) =>
				systemPrivateKey = PrivateKey.import(loggedInAccount.privateInfo.systemPrivateKey)

				systemPrivateKey.decrypt accountRecovery, (err, accountKeyBuf) =>
					if err
						cb err
						return

					accountKey = SymmetricEncryptionKey.import(accountKeyBuf.toString())
					cb()
			(cb) =>
				Fs.readFile Path.join(userDir, 'private-info'), (err, buf) ->
					if err
						cb new IOError err
						return

					privateInfo = JSON.parse accountKey.decrypt buf
					cb()
		], (err) =>
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

				cb new IOError err
				return

			# Find the highest (i.e. most recent) account key ID
			accountKeyId = Imm.List(fileNames)
			.filter (fileName) ->
				return fileName.startsWith 'account-key-'
			.map (fileName) ->
				return Number(fileName['account-key-'.length...])
			.max()

			cb null, (accountKeyId or 0)

# DecryptedAccount objects contain both the private and public information in a
# user account, including encryption keys, and provide related functionality.
# DecryptedAccount objects can be obtained using Account's "decrypt" methods.
class DecryptedAccount extends Account
	constructor: (@dataDirectory, @userName, @publicInfo, @privateInfo, @_accountKey, code) ->
		if code isnt 'privateaccess'
			# See Account.decrypt* instead
			throw new Error "DecryptedAccount constructor should only be used internally"

		@_userDir = getUserDir @dataDirectory, @userName

	# Updates this user account's password.
	#
	# Errors:
	# - UnknownUserNameError if this account no longer exists
	# - IOError
	#
	# (string newPassword, function cb(Error err)) -> undefined
	setPassword: (newPassword, cb) =>
		# BEGIN v1.3.1 migration
		if Fs.existsSync Path.join(@_userDir, 'auth-params')
			# This account is in the old format.

			systemUserDir = Path.join(@dataDirectory, '_users', '_system')

			kdfParams = generateKdfParams()
			systemPublicKey = null
			pwEncryptionKey = null
			accountRecovery = null

			Async.series [
				(cb) =>
					Fs.readFile Path.join(systemUserDir, 'public-key'), (err, buf) =>
						if err
							cb new IOError err
							return

						systemPublicKey = PublicKey.import(buf.toString())
						cb()
				(cb) =>
					SymmetricEncryptionKey.derive newPassword, kdfParams, (err, result) =>
						if err
							cb err
							return

						pwEncryptionKey = result
						cb()
				(cb) =>
					accountKeyFile = JSON.stringify {
						accountKey: Base64url.encode pwEncryptionKey.encrypt(@_accountKey.export())
						kdfParams
					}

					Fs.writeFile Path.join(@_userDir, 'account-key-1'), accountKeyFile, (err) =>
						if err
							cb new IOError err
							return

						cb()
				(cb) =>
					systemPublicKey.encrypt @_accountKey.export(), (err, result) =>
						if err
							cb err
							return

						accountRecovery = result
						cb()
				(cb) =>
					Fs.writeFile Path.join(@_userDir, 'account-recovery'), accountRecovery, (err) =>
						if err
							cb new IOError err
							return

						cb()
				(cb) =>
					privateInfoEncrypted = @_accountKey.encrypt JSON.stringify(@privateInfo)

					Fs.writeFile Path.join(@_userDir, 'private-info'), privateInfoEncrypted, (err) =>
						if err
							cb new IOError err
							return

						cb()
				(cb) =>
					Fs.unlink Path.join(@_userDir, 'private-keys'), (err) =>
						if err
							cb new IOError err
							return

						cb()
				(cb) =>
					Fs.unlink Path.join(@_userDir, 'auth-params'), (err) =>
						if err
							cb new IOError err
							return

						cb()
			], cb
			return
		# END v1.3.1 migration

		kdfParams = generateKdfParams()
		nextAccountKeyId = null
		pwEncryptionKey = null

		Async.series [
			(cb) =>
				@_findMaxAccountKeyId (err, result) =>
					if err
						cb err
						return

					nextAccountKeyId = result + 1
					cb()
			(cb) =>
				SymmetricEncryptionKey.derive newPassword, kdfParams, (err, result) =>
					if err
						cb err
						return

					pwEncryptionKey = result
					cb()
			(cb) =>
				accountKeyEncoded = Base64url.encode pwEncryptionKey.encrypt(@_accountKey.export())
				data = {kdfParams, accountKey: accountKeyEncoded}

				Fs.writeFile Path.join(@_userDir, "account-key-#{nextAccountKeyId}"), JSON.stringify(data), (err) =>
					if err
						cb new IOError err
						return

					cb()
		], cb

generateKdfParams = ->
	return {
		salt: generateSalt()
		iterationCount: 600000 # higher is more secure, but slower
	}

getUserDir = (dataDir, userName) ->
	unless userNameRegex.exec userName
		throw new Error "invalid characters in user name"

	return Path.join dataDir, '_users', userName

class UserNameTakenError extends CustomError
class UnknownUserNameError extends CustomError
class IncorrectPasswordError extends CustomError
class DeactivatedAccountError extends CustomError

module.exports = {
	isAccountSystemSetUp
	listUserNames
	Account
	DecryptedAccount
	UserNameTakenError
	UnknownUserNameError
	IncorrectPasswordError
	DeactivatedAccountError
}