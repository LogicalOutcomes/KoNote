# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Base64url = require 'base64url'
Crypto = require 'crypto'
Joi = require 'joi'

# Generate a unique ID.
# Outputs a string containing only a-z, A-Z, 0-9, "-", and "_".
# Expected to be unique until 2^60 IDs have been generated.
# To avoid collisions, create fewer than 2^40 IDs.
generateId = ->
	return Base64url.encode(Crypto.randomBytes(15))

# All object IDs match this pattern
IdSchema = Joi.string().regex(/^[a-zA-Z0-9_-]+$/)

TimestampFormat = 'YYYYMMDDTHHmmssSSSZZ'

isValidJSON = (jsonString) ->
	try
		json = JSON.parse jsonString
		return true if json? and typeof json is "object"
	catch err
		console.error "Invalid JSON:", jsonString
		return false

# This class allows new error types to be created easily without breaking stack
# traces, toString, etc.
#
# Example:
# 	class MyError extends CustomError
#
# MyError will accept a single, optional argument `message`.
#
# Example:
# 	class MyError2 extends CustomError
# 		constructor: (message, anotherArgument) ->
# 			super message # must call superclass constructor
# 			@anotherArgument = anotherArgument
#
# MyError2 will accept two mandatory arguments: `message` and `anotherArgument`.
class CustomError extends Error
	constructor: (message) ->
		@name = @constructor.name
		@message = message
		Error.captureStackTrace @, @constructor

class ObjectNotFoundError extends CustomError
	constructor: ->
		super()

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
	isValidJSON
}
