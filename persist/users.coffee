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
			return dirName isnt '_system'
		.filter (dirName) ->
			return userNameRegex.exec(dirName)

		cb null, userNames

class Account
	constructor: (@dataDirectory, @userName, @publicInfo, code) ->
		if code isnt 'privateaccess'
			# See Account.read instead
			throw new Error "Account constructor should only be used internally"

		@_userDir = getUserDir @dataDirectory, @userName

	# First time set up of user account directory
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
			(cb) ->
				PrivateKey.generate (err, result) ->
					if err
						cb err
						return

					privateInfo.systemPrivateKey = result.export()
					systemPublicKey = result.getPublicKey().export()
					cb()
			(cb) ->
				Fs.mkdir Path.join(dataDir, '_users', '_system'), cb
			(cb) ->
				Fs.writeFile Path.join(dataDir, '_users', '_system', 'public-key'), systemPublicKey, cb
		], (err) ->
			if err
				cb err
				return

			systemAccount = new DecryptedAccount(dataDir, '_system', publicInfo, privateInfo, null, 'privateaccess')
			cb null, systemAccount

	@create: (loggedInAccount, userName, password, accountType, cb) ->
		unless accountType in ['normal', 'admin']
			cb new Error "unknown account type #{JSON.stringify accountType}"
			return

		userName = userName.toLowerCase()

		userDir = getUserDir loggedInAccount.dataDirectory, userName

		publicInfo = {accountType, isActive: true}
		kdfParams = generateKdfParams()
		accountEncryptionKey = SymmetricEncryptionKey.generate()

		systemPublicKey = null
		pwEncryptionKey = null

		Async.series [
			(cb) ->
				publicKeyPath = Path.join(loggedInAccount.dataDirectory, '_users', '_system', 'public-key')

				Fs.readFile publicKeyPath, (err, buf) ->
					if err
						cb err
						return

					systemPublicKey = PublicKey.import(buf.toString())
					cb()
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
				encryptedAccountKey = systemPublicKey.encrypt accountEncryptionKey.export()

				Fs.writeFile accountRecoveryPath, encryptedAccountKey, cb
			(cb) ->
				privateInfoPath = Path.join(userDir, 'private-info')

				privateInfo = {
					globalEncryptionKey: loggedInAccount.privateInfo.globalEncryptionKey
				}

				if accountType is 'admin'
					Assert.strictEqual loggedInAccount.publicInfo.accountType, 'admin', 'only admins can create admins'

					privateInfo.systemPrivateKey = loggedInAccount.privateInfo.systemPrivateKey

				encryptedData = accountEncryptionKey.encrypt JSON.stringify privateInfo

				Fs.writeFile privateInfoPath, encryptedData, cb
		], (err) ->
			if err
				cb err
				return

			cb null, new Account loggedInAccount.dataDirectory, userName, publicInfo, 'privateaccess'

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
				Async.each accountKeyFileNames.toArray(), (fileName, cb) =>
					Fs.unlink Path.join(@_userDir, fileName), cb
				, cb
		], cb

	# Returns IncorrectPasswordError if password is incorrect
	checkPassword: (userPassword, cb) =>
		# Not all of decryptWithPassword is actually needed to check the
		# password.  If needed, this can be reimplemented to be more efficient.

		@decryptWithPassword userPassword, (err, result) =>
			if err
				cb err
				return

			cb()

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

			Async.series [
				(cb) =>
					Fs.readFile Path.join(@_userDir, 'auth-params'), (err, result) =>
						if err
							cb err
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
							cb err
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
							cb err
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

					Fs.writeFile Path.join(@_userDir, 'account-key-1'), accountKeyFile, cb
				(cb) =>
					accountRecovery = systemPublicKey.encrypt(accountKey.export())

					Fs.writeFile Path.join(@_userDir, 'account-recovery'), accountRecovery, cb
				(cb) =>
					privateInfo = {
						globalEncryptionKey: globalEncryptionKey.export()
					}

					if @publicInfo.accountType is 'admin'
						privateInfo.systemPrivateKey = systemPrivateKey.export()

					privateInfoEncrypted = accountKey.encrypt JSON.stringify(privateInfo)

					Fs.writeFile Path.join(@_userDir, 'private-info'), privateInfoEncrypted, cb
				(cb) =>
					Fs.unlink Path.join(@_userDir, 'private-keys'), cb
				(cb) =>
					Fs.unlink Path.join(@_userDir, 'auth-params'), cb
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
						cb err
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

						cb err
						return

					accountKeyBuf = PrivateKey.import(loggedInAccount.privateInfo.systemPrivateKey).decrypt buf
					accountKey = SymmetricEncryptionKey.import(accountKeyBuf.toString())
					cb()
			(cb) =>
				Fs.readFile Path.join(userDir, 'private-info'), (err, buf) ->
					if err
						cb err
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

				cb err
				return

			# Find the highest (i.e. most recent) account key ID
			accountKeyId = Imm.List(fileNames)
			.filter (fileName) ->
				return fileName.startsWith 'account-key-'
			.map (fileName) ->
				return Number(fileName['account-key-'.length...])
			.max()

			cb null, (accountKeyId or 0)

class DecryptedAccount extends Account
	constructor: (@dataDirectory, @userName, @publicInfo, @privateInfo, @_accountKey, code) ->
		if code isnt 'privateaccess'
			# See Account.decrypt* instead
			throw new Error "DecryptedAccount constructor should only be used internally"

		@_userDir = getUserDir @dataDirectory, @userName

	setPassword: (newPassword, cb) =>
		# BEGIN v1.3.1 migration
		if Fs.existsSync Path.join(@_userDir, 'auth-params')
			# This account is in the old format.

			systemUserDir = Path.join(@dataDirectory, '_users', '_system')

			kdfParams = generateKdfParams()
			systemPublicKey = null
			pwEncryptionKey = null

			Async.series [
				(cb) =>
					Fs.readFile Path.join(systemUserDir, 'public-key'), (err, buf) =>
						if err
							cb err
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

					Fs.writeFile Path.join(@_userDir, 'account-key-1'), accountKeyFile, cb
				(cb) =>
					accountRecovery = systemPublicKey.encrypt(@_accountKey.export())

					Fs.writeFile Path.join(@_userDir, 'account-recovery'), accountRecovery, cb
				(cb) =>
					privateInfoEncrypted = @_accountKey.encrypt JSON.stringify(@privateInfo)

					Fs.writeFile Path.join(@_userDir, 'private-info'), privateInfoEncrypted, cb
				(cb) =>
					Fs.unlink Path.join(@_userDir, 'private-keys'), cb
				(cb) =>
					Fs.unlink Path.join(@_userDir, 'auth-params'), cb
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

				Fs.writeFile Path.join(@_userDir, "account-key-#{nextAccountKeyId}"), JSON.stringify(data), cb
		], cb

class UserNameTakenError extends CustomError
class UnknownUserNameError extends CustomError
class IncorrectPasswordError extends CustomError
class DeactivatedAccountError extends CustomError

module.exports = {
	isAccountSystemSetUp
	listAccounts
	Account
	DecryptedAccount
	UserNameTakenError
	UnknownUserNameError
	IncorrectPasswordError
	DeactivatedAccountError
}
