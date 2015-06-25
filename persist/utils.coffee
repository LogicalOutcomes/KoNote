Base64url = require 'base64url'
Crypto = require 'crypto'
Joi = require 'joi'

# Generate a unique ID.
# Outputs a string containing only a-z, A-Z, 0-9, "-", and "_".
# Guaranteed to be unique with overwhelming probability.
generateId = ->
	return Base64url.encode(Crypto.randomBytes(32))

# All object IDs match this pattern
IdSchema = Joi.string().regex(/^[a-zA-Z0-9_-]+$/)

validate = (value, schema, cb) ->
	results = Joi.validate value, schema

	if results.error?
		cb results.error
		return

	cb null, results.value

TimestampFormat = 'YYYYMMDDTHHmmssSSSZZ'

class ObjectNotFoundError extends Error
	constructor: ->
		super

class IOError extends Error
	constructor: (cause) ->
		super()

		@cause = cause
		@message = cause.message
		@stack = cause.stack

		return
	toString: ->
		return "IOError: " + (@cause?.toString())

module.exports = {
	IOError
	IdSchema
	ObjectNotFoundError
	TimestampFormat
	generateId
	validate
}
