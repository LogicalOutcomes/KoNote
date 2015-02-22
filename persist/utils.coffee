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

# Defines which strings are safe to use as a file name.
# Note: this is mainly to prevent Windows from blowing up.
# We don't want users to be able to use '/' or '\' because paths.
# We also don't want users to be able to use '.' because that's how we delimit
# the pieces of our file names.
PathSafeString = Joi.string().regex(/^[ 'a-zA-Z0-9_-]+$/)

validate = (value, schema, cb) ->
	results = Joi.validate value, schema

	if results.error?
		cb results.error
		return

	cb null, results.value

# Safe for including in file paths
SafeTimestampFormat = 'YYYYMMDDTHHmmss'

class ObjectNotFoundError extends Error
	constructer: ->
		super

validateClientName = (name) ->
	first = name.get('first')
	middle = name.get('middle')
	last = name.get('last')

	if Joi.validate(first, PathSafeString).error?
		throw new Error "invalid client first name: #{JSON.stringify first}"

	if middle? and Joi.validate(middle, PathSafeString).error?
		throw new Error "invalid client middle name: #{JSON.stringify middle}"

	if Joi.validate(last, PathSafeString).error?
		throw new Error "invalid client last name: #{JSON.stringify last}"

module.exports = {
	IdSchema
	ObjectNotFoundError
	PathSafeString
	SafeTimestampFormat
	generateId
	validate
	validateClientName
}
