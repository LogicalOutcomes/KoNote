# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Base64url = require 'base64url'
Crypto = require 'crypto'
Imm = require 'immutable'
Joi = require 'joi'

# Generate a unique ID.
# Outputs a string containing only a-z, A-Z, 0-9, "-", and "_".
# Expected to be unique until 2^60 IDs have been generated.
# To avoid collisions, create fewer than 2^40 IDs.
generateId = ->
	return Base64url.encode(Crypto.randomBytes(15))

# generate a temporary ID
generateFastId = ->
	return new Date().getTime().toString(36) + Math.random().toString(36).slice(-12)

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

# Persistent objects come with metadata that makes it difficult to compare
# revisions (e.g. timestamp).  This method removes those attributes.
stripMetadata = (persistObj) ->
	return persistObj
	.delete('revisionId')
	.delete('author')
	.delete('timestamp')
	.delete('_dirPath')

# Extract from `obj` the ID field for every ancestor object.
#
# Some collections exist within another object.  E.g. a collection of
# progress notes exists inside every client file object.  Suppose we want
# to `list()` one of those progress note collections.  In order to know
# which progress notes folder to read, we need to know the ID of the client
# file that contains it.  That client file is called the "parent" of the
# collection.
#
# This function returns a list of the IDs needed to figure out where a
# collection is located.  Suppose we want to access the "comments"
# collection at `data/clientFiles/123/progNotes/234/comments/`.  This
# function would access the object's `clientFileId` and `progNoteId`, and
# return `["123", "234"]`.  In this example, client file 123 and prognote
# 234 are "ancestors" of the comments collection.
extractContextualIds = (obj, context) ->
	return context.map (contextDef) ->
		contextIdProp = contextDef.name + 'Id'

		if obj.has(contextIdProp)
			return obj.get(contextIdProp)

		throw new Error "Object is missing field #{JSON.stringify contextIdProp}"

flattenModelDefs = (modelDefs, context=Imm.List()) ->
	result = Imm.Map()

	for modelDef in modelDefs
		# Add this model def to result
		result = result.set(modelDef.collectionName, Imm.Map({modelDef, context}))

		# Recurse over this model def's children, and merge them into result
		if modelDef.children
			descendantModelDefs = flattenModelDefs modelDef.children, context.push(modelDef)
			result = result.merge descendantModelDefs

	return result


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
	extractContextualIds
	flattenModelDefs
	generateId
	generateFastId
	isValidJSON
	stripMetadata
}
