# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module handles all logic related to login sessions, including logging
# in, logging out, and managing encryption keys.

Async = require 'async'
Fs = require 'fs'
Path = require 'path'
Config = require '../config'

{SymmetricEncryptionKey} = require './crypto'
DataModels = require './dataModels'
{
	Account, DecryptedAccount
	
	UnknownUserNameError
	InvalidUserNameError
	IncorrectPasswordError
	DeactivatedAccountError	
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
			throw new Error "invalid account object"

		@userName = @account.userName
		@accountType = @account.publicInfo.accountType
		@globalEncryptionKey = SymmetricEncryptionKey.import @account.privateInfo.globalEncryptionKey

		@_ended = false

		@persist = DataModels.getApi(@backend, @)
		timeoutSpec = Config.timeout

		@timeoutMs = timeoutSpec.duration * 60000
		@warnDurations = {
			initial: @timeoutMs - (timeoutSpec.warnings.initial * 60000)
			final: @timeoutMs - (timeoutSpec.warnings.final * 60000)
		}

		@resetTimeout()

	resetTimeout: ->
		# Clear all traces of timeouts
		if @timeout then clearTimeout @timeout
		if @initialWarning then clearTimeout @initialWarning
		if @finalWarning then clearTimeout @finalWarning

		@timeout = null
		@initialWarning = null
		@finalWarning = null		

		# Keeping track of notification delivery to prevent duplicates
		@initialWarningDelivered = null
		@finalWarningDelivered = null

		# Initiate timeouts
		@initialWarning = setTimeout(=> 
			@_triggerEvent('timeout:initialWarning')
		, @warnDurations.initial)

		@finalWarning = setTimeout(=>
			@_triggerEvent('timeout:finalWarning')
		, @warnDurations.final)

		@timeout = setTimeout(=>
			@_triggerEvent('timeout:timedOut')
		, @timeoutMs)

	_triggerEvent: (eventName) => @persist.eventBus.trigger eventName

	isAdmin: ->
		return @accountType is 'admin'

	confirmPassword: (password, cb) ->
		@account.checkPassword password, cb

	logout: ->
		if @_ended
			throw new Error "session has already ended"

		@_ended = true

module.exports = {
	login
	UnknownUserNameError
	InvalidUserNameError
	IncorrectPasswordError
	DeactivatedAccountError
}
