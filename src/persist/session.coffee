# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module handles all logic related to login sessions, including logging
# in, logging out, and managing encryption keys.

Config = require '../config'

{SymmetricEncryptionKey} = require './crypto'
DataModels = require './dataModels'
{
	Account, DecryptedAccount

	UnknownUserNameError
	InvalidUserNameError
	IncorrectPasswordError
	DeactivatedAccountError
	AccountTypeError
} = require './users'

login = (userName, password, backend, cb) ->
	Account.read backend, userName, (err, account) ->
		if err
			cb err
			return

		account.decryptWithPassword password, (err, decryptedAccount) ->
			if err
				cb err
				return

			cb null, new Session(decryptedAccount, backend)

createBackend = (backendConfig) ->

class Session
	constructor: (@account, @backend) ->
		unless @account instanceof DecryptedAccount
			throw new Error "Invalid account object"

		@userName = @account.userName
		@displayName = @account.publicInfo.displayName
		@accountType = @account.publicInfo.accountType
		@globalEncryptionKey = SymmetricEncryptionKey.import @account.privateInfo.globalEncryptionKey

		@_ended = false

		@persist = DataModels.getApi(@backend, @)
		timeoutSpec = Config.timeout

		@timeoutMs = timeoutSpec.duration * 60000

		@warnDurations = {
			final: @timeoutMs - (timeoutSpec.warnings.final * 60000)
		}

		@resetTimeout()

	resetTimeout: ->
		# Clear all traces of timeouts
		if @timeout then clearTimeout @timeout
		if @finalWarning then clearTimeout @finalWarning

		@timeout = null
		@finalWarning = null

		# Keeping track of notification delivery to prevent duplicates
		@finalWarningDelivered = null

		# Initiate timeout countdowns
		@finalWarning = setTimeout(=>
			@persist.eventBus.trigger 'timeout:finalWarning'
		, @warnDurations.final)

		@timeout = setTimeout(=>
			@persist.eventBus.trigger 'timeout:timedOut'
		, @timeoutMs)

	isAdmin: ->
		# required for basic admins to create client files. todo: tidy up
		return @accountType is 'admin' or 'basicAdmin'

	confirmPassword: (password, cb) ->
		@account.checkPassword password, cb

	logout: ->
		if @_ended
			throw new Error "Session has already ended"

		@_ended = true

module.exports = {
	login
	UnknownUserNameError
	InvalidUserNameError
	IncorrectPasswordError
	DeactivatedAccountError
	AccountTypeError
}
