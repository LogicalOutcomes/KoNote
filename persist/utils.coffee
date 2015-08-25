# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Base64url = require 'base64url'
Crypto = require 'crypto'
Joi = require 'joi'

# TODO Persist modules shouldn't depend on KoNote modules
{CustomError} = require '../utils'

# Generate a unique ID.
# Outputs a string containing only a-z, A-Z, 0-9, "-", and "_".
# Guaranteed to be unique with overwhelming probability.
generateId = ->
	return Base64url.encode(Crypto.randomBytes(32))

# All object IDs match this pattern
IdSchema = Joi.string().regex(/^[a-zA-Z0-9_-]+$/)

TimestampFormat = 'YYYYMMDDTHHmmssSSSZZ'

class ObjectNotFoundError extends CustomError
	constructor: ->
		super

class IOError extends CustomError
	constructor: (cause) ->
		super()

		@cause = cause
		@message = cause.message
		@stack = cause.stack

		return
	toString: ->
		return "IOError: " + (@cause?.toString())

module.exports = {
	CustomError
	IOError
	IdSchema
	ObjectNotFoundError
	TimestampFormat
	generateId
}
