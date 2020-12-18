# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module implements the core operations of the persistent object store.
#
# The Persist package generates an API based on the data models it is
# configured with.  Within that API, there is an interface for each collection
# (e.g. `persist.clientFiles` or `persist.metrics`).  That interface is called
# a Collection API, i.e. an API for a specific collection.
#
# The `createCollectionApi` function generates an API for a single collection
# based on a data model (and some additional information such as the current
# session).  The `persist/apiBuilder` module uses this function on every data
# model definition.

Async = require 'async'
Joi = require 'joi'
Imm = require 'immutable'
Moment = require 'moment'

{
	IOError
	IdSchema
	ObjectNotFoundError
	TimestampFormat
	generateId
} = require './utils'

joiValidationOptions = Object.freeze {
	# I would like to set this to false, but Joi doesn't seem to support date
	# string validation without convert: true
	convert: true

	# Any properties that are not required must be explicitly marked optional.
	presence: 'required'
}

# Create an API based on the specified model definition.
#
# session: a Session object
# eventBus: the EventBus to which object mutation events should be dispatched
# context: a List of model definitions.  Each model definition is an ancestor
# of this collection, ordered from outermost (i.e. top-level) to innermost.
#
# Example:
#	Imm.List([clientFileModelDef, progNoteModelDef])
#
# modelDef: the data model definition that defines this collection
createCollectionApi = (backend, session, eventBus, context, modelDef) ->
	# Define a series of methods that this collection API will (or might) contain.
	# These methods correspond to what is documented in the wiki.
	# See the wiki for instructions on their use.

	create = (obj, cb) ->
		# The object hasn't been created yet, so it shouldn't have any of these
		# metadata fields.  If it does, it probably indicates a bug.

		if obj.has('id')
			cb new Error "new objects cannot already have an ID"
			return

		if obj.has('revisionId')
			cb new Error "new objects cannot already have a revision ID"
			return

		# We allow explicit metadata for development purposes, such as seeding.

		# This is commented out for now, to prevent the application failing here
		# when trying to import data that might somehow still have these metadata properties attached
		# (which get overwritten here anyway)
		
		# if process.env.NODE_ENV isnt 'development'
		# 	if obj.has('author')
		# 		cb new Error "new objects cannot already have an author"
		# 		return

		# 	if obj.has('timestamp')
		# 		cb new Error "new objects cannot already have a timestamp"
		# 		return

		# 	if obj.has('authorDisplayName')
		# 		cb new Error "new objects cannot already have a displayName"
		# 		return

		# Add metadata fields
		obj = obj
		.set 'id', generateId()
		.set 'revisionId', generateId()
		.set 'author', obj.get('author') or session.userName
		.set 'authorDisplayName', session.displayName or session.userName
		.set 'timestamp', obj.get('timestamp') or Moment().format(TimestampFormat)

		# Validate object before passing to backend
		schema = prepareSchema modelDef.schema, context
		validation = Joi.validate obj.toJS(), schema, joiValidationOptions

		if validation.error?
			process.nextTick ->
				cb validation.error
			return

		backend.createObject Imm.fromJS(validation.value), context, modelDef, (err) ->
			if err
				cb err
				return

			# Return a copy of the newly created object, complete with metadata
			cb null, obj

	list = (contextualIds..., cb) ->
		contextualIds = Imm.List(contextualIds)

		# API user must provide IDs for each of the ancestor objects,
		# otherwise, we don't know where to look
		if contextualIds.size isnt context.size
			cb new Error "wrong number of arguments"
			return

		backend.listObjectsInCollection contextualIds, context, modelDef, (err, headers) ->
			if err
				cb err
				return

			cb null, headers

	read = (contextualIds..., id, cb) ->
		contextualIds = Imm.List(contextualIds)

		# API user must provide enough IDs to figure out where this collection
		# is located.
		if contextualIds.size isnt context.size
			cb new Error "wrong number of arguments"
			return

		backend.readObject contextualIds, id, context, modelDef, (err, obj) ->
			if err
				cb err
				return

			# Validate against the collection's schema
			schema = prepareSchema modelDef.schema, context
			validation = Joi.validate obj.toJS(), schema, joiValidationOptions

			if validation.error?
				cb validation.error
				return

			cb null, Imm.fromJS validation.value

	createRevision = (obj, cb) ->
		# The object should already have been created, so it should already
		# have an ID.
		unless obj.has('id')
			cb new Error "missing property 'id'"
			return

		objId = obj.get('id')

		# Add the relevant metadata fields
		obj = obj
		.set 'revisionId', generateId()
		.set 'author', session.userName
		.set 'authorDisplayName', session.displayName or session.userName
		.set 'timestamp', Moment().format(TimestampFormat)

		# Validate object before passing to backend
		schema = prepareSchema modelDef.schema, context
		validation = Joi.validate obj.toJS(), schema, joiValidationOptions

		if validation.error?
			process.nextTick ->
				cb validation.error
			return

		backend.createObjectRevision Imm.fromJS(validation.value), context, modelDef, (err) ->
			if err
				cb err
				return

			cb null, obj

	listRevisions = (contextualIds..., id, cb) ->
		contextualIds = Imm.List(contextualIds)

		# Need enough context to locate this object's collection
		if contextualIds.size isnt context.size
			cb new Error "wrong number of arguments"
			return

		backend.listObjectRevisions contextualIds, id, context, modelDef, cb

	readRevisions = (contextualIds..., id, cb) ->
		contextualIds = Imm.List(contextualIds)

		unless cb
			cb new Error "readRevisions must be provided a callback"
			return

		# Need enough information to determine where this object's collection
		# is located
		if contextualIds.size isnt context.size
			cb new Error "wrong number of arguments"
			return

		# List all of this object's revisions
		listRevisions contextualIds.toArray()..., id, (err, revisions) ->
			if err
				cb err
				return

			# Read the revisions one-by-one
			Async.map revisions.toArray(), (rev, cb) ->
				readRevision contextualIds.toArray()..., id, rev.get('revisionId'), cb
			, (err, results) ->
				if err
					cb err
					return

				cb null, Imm.List(results)

	readLatestRevisions = (contextualIds..., id, maxRevisionCount, cb) ->
		contextualIds = Imm.List(contextualIds)

		unless cb
			throw new Error "readLatestRevisions must be provided a callback"

		# Need object IDs of any ancestor objects in order to locate this
		# object's collection
		if contextualIds.size isnt context.size
			cb new Error "wrong number of arguments"
			return

		if maxRevisionCount < 0
			cb new Error "maxRevisionCount must be >= 0"
			return

		# We could theoretically optimize for maxRevisionCount=0 here.
		# However, this would cause requests for non-existant objects to succeed.

		# List all of the object's revisions
		listRevisions contextualIds.toArray()..., id, (err, revisions) ->
			if err
				cb err
				return

			# Only access the most recent revisions
			revisions = revisions.takeLast maxRevisionCount

			# Read only those revisions
			Async.map revisions.toArray(), (rev, cb) ->
				readRevision contextualIds.toArray()..., id, rev.get('revisionId'), cb
			, (err, results) ->
				if err
					cb err
					return

				cb null, Imm.List(results)

	readRevision = (contextualIds..., id, revisionId, cb) ->
		contextualIds = Imm.List(contextualIds)

		unless cb
			throw new Error "readLatestRevisions must be provided a callback"

		# Need object IDs of any ancestor objects in order to locate this
		# object's collection
		if contextualIds.size isnt context.size
			cb new Error "wrong number of arguments"
			return

		backend.readObjectRevision contextualIds, id, revisionId, context, modelDef, (err, obj) ->
			if err
				cb err
				return

			# Validate against the collection's schema
			schema = prepareSchema modelDef.schema, context
			validation = Joi.validate obj.toJS(), schema, joiValidationOptions

			if validation.error?
				cb validation.error
				return

			cb null, Imm.fromJS validation.value

	# Build and return the actual collection API, using the previously defined methods
	result = {
		create,
		list,
	}

	if modelDef.isMutable
		# Only mutable collections have methods related to revisions
		result.createRevision = createRevision
		result.listRevisions = listRevisions
		result.readRevisions = readRevisions
		result.readLatestRevisions = readLatestRevisions
	else
		# Immutable collections just get the basic read method
		result.read = read

	return result

# Add metadata fields to object schema
prepareSchema = (schema, context) ->
	# The schema can be an array of possible schemas
	# (see Joi documentation)
	if Array.isArray schema
		return (prepareSchema(subschema, context) for subschema in schema)

	# We assume at this point that schema is a Joi.object()

	newKeys = {
		id: IdSchema
		revisionId: IdSchema
		timestamp: Joi.date().format(TimestampFormat).raw()
		author: Joi.string().regex(/^[a-zA-Z0-9_-]+$/)
		authorDisplayName: Joi.string().allow('').optional()
	}

	# Each context type needs its own ID field
	context.forEach (contextDef) ->
		# Add another entry to newKeys
		typeName = contextDef.name
		newKeys[typeName + 'Id'] = IdSchema

	# Extend the original set of permissible keys
	return schema.keys(newKeys)

module.exports = {
	createCollectionApi
}
