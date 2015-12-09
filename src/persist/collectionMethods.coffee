# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Assert = require 'assert'
Async = require 'async'
Base64url = require 'base64url'
BufferEq = require 'buffer-equal-constant-time'
Fs = require 'fs'
Joi = require 'joi'
Imm = require 'immutable'
Moment = require 'moment'
Path = require 'path'

Atomic = require './atomic'
Crypto = require './crypto'

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
# context: a List of Maps.  Each Map represents an ancestor type, ordered from
# outermost (i.e. top-level) to innermost.  Example: Imm.List([
# 	Imm.Map({
# 		definition: modelDefOuter
# 		api: apiOuter
# 	})
# 	Imm.Map({
# 		definition: modelDefInner
# 		api: apiInner
# 	})
# ])
createCollectionApi = (session, eventBus, context, modelDef) ->
	childCollectionNames = Imm.List(modelDef.children).map (childDef) ->
		return childDef.collectionName

	tmpDirPath = Path.join(session.dataDirectory, '_tmp')

	create = (obj, cb) ->
		if obj.has('id')
			cb new Error "new objects cannot already have an ID"
			return

		if obj.has('revisionId')
			cb new Error "new objects cannot already have a revision ID"
			return

		if obj.has('author')
			cb new Error "new objects cannot already have an author"
			return

		if obj.has('timestamp')
			cb new Error "new objects cannot already have a timestamp"
			return

		contextualIds = extractContextualIds obj

		obj = obj
		.set 'id', generateId()
		.set 'revisionId', generateId()
		.set 'author', session.userName
		.set 'timestamp', Moment().format(TimestampFormat)

		fileNameEncryptionKey = getFileNameEncryptionKey()

		destObjDir = null
		objDir = null
		objDirOp = null

		Async.series [
			(cb) ->
				getParentDir contextualIds, (err, parentDir) ->
					if err
						cb err
						return

					fileName = createObjectFileName(obj, modelDef.indexes)
					encryptedFileName = Base64url.encode fileNameEncryptionKey.encrypt fileName
					destObjDir = Path.join(
						parentDir
						modelDef.collectionName
						encryptedFileName
					)
					cb()
			(cb) ->
				# In order to make the operation atomic, we write to a
				# temporary object directory first, then commit it later.
				Atomic.writeDirectory destObjDir, tmpDirPath, (err, tmpObjDir, op) ->
					if err
						cb new IOError err
						return

					objDir = tmpObjDir
					objDirOp = op
					cb()
			(cb) ->
				# Create subdirs for subcollection
				Async.each modelDef.children, (child, cb) ->
					childDir = Path.join(objDir, child.collectionName)
					Fs.mkdir childDir, (err) ->
						if err
							cb new IOError err
							return

						cb()
				, cb
			(cb) ->
				revFileName = createRevisionFileName(obj)
				encryptedRevFileName = Base64url.encode fileNameEncryptionKey.encrypt revFileName

				revFilePath = Path.join(objDir, encryptedRevFileName)

				writeObjectFile obj, revFilePath, contextualIds, cb
			(cb) ->
				objDirOp.commit cb
		], (err) ->
			if err
				cb err
				return

			# Dispatch event via event bus
			eventBus.trigger "create:#{modelDef.name}", obj

			cb null, obj

	list = (contextualIds..., cb) ->
		if contextualIds.length isnt context.size
			cb new Error "wrong number of arguments"
			return

		collectionDir = null
		fileNames = null

		Async.series [
			(cb) ->
				getParentDir contextualIds, (err, parentDir) ->
					if err
						cb err
						return

					collectionDir = Path.join(
						parentDir
						modelDef.collectionName
					)
					cb()
			(cb) ->
				Fs.readdir collectionDir, (err, results) ->
					if err
						cb new IOError err
						return

					fileNames = results
					cb()
		], (err) ->
			if err
				cb err
				return

			result = Imm.List(fileNames)
				.map (fileName) ->
					decryptedFileName = getFileNameEncryptionKey().decrypt(
						Base64url.toBuffer fileName
					)
					[indexValues..., id] = decodeFileName(decryptedFileName, modelDef.indexes.length + 1)

					result = Imm.Map({
						id: Base64url.encode id
						_dirPath: Path.join(collectionDir, fileName)
					})

					for indexedProp, i in modelDef.indexes
						result = result.setIn indexedProp, indexValues[i].toString()

					return result

			cb null, result

	read = (contextualIds..., id, cb) ->
		if contextualIds.length isnt context.size
			cb new Error "wrong number of arguments"
			return

		lookupObjDirById contextualIds, id, (err, objDir) ->
			if err
				cb err
				return

			Fs.readdir objDir, (err, revisionFiles) ->
				if err
					cb new IOError err
					return

				revisionFiles = revisionFiles.filter (fileName) ->
					return not childCollectionNames.contains(fileName)

				if revisionFiles.length > 1
					cb new Error "object at #{JSON.stringify objDir} is immutable but has multiple revisions"
					return

				if revisionFiles.length < 1
					cb new Error "missing revisions in #{JSON.stringify objDir}"
					return

				revisionFile = revisionFiles[0]
				revisionFilePath = Path.join(objDir, revisionFile)

				readObjectFile revisionFilePath, contextualIds, id, cb

	createRevision = (obj, cb) ->
		unless obj.has('id')
			cb new Error "missing property 'id'"
			return

		contextualIds = extractContextualIds obj

		obj = obj
		.set 'revisionId', generateId()
		.set 'author', session.userName
		.set 'timestamp', Moment().format(TimestampFormat)

		fileNameEncryptionKey = getFileNameEncryptionKey()

		objDir = null
		Async.series [
			(cb) ->
				lookupObjDirById contextualIds, obj.get('id'), (err, result) ->
					if err
						cb err
						return

					objDir = result
					cb()
			(cb) ->
				revFileName = createRevisionFileName(obj)
				encryptedRevFileName = Base64url.encode fileNameEncryptionKey.encrypt revFileName

				revFilePath = Path.join(objDir, encryptedRevFileName)

				writeObjectFile obj, revFilePath, contextualIds, cb
			(cb) ->
				# When an indexed property changes, we need to rename the dir
				parentDirPath = Path.dirname objDir
				expectedDecryptedDirName = createObjectFileName(obj, modelDef.indexes)

				currentEncryptedDirName = Path.basename objDir
				currentDecryptedDirName = fileNameEncryptionKey.decrypt(
					Base64url.toBuffer currentEncryptedDirName
				)

				if BufferEq(expectedDecryptedDirName, currentDecryptedDirName)
					cb()
					return

				# But sometimes expectations don't meet reality
				currentDirPath = Path.join(parentDirPath, currentEncryptedDirName)
				newDirName = Base64url.encode fileNameEncryptionKey.encrypt expectedDecryptedDirName
				newDirPath = Path.join(parentDirPath, newDirName)

				objDir = newDirPath
				Fs.rename currentDirPath, newDirPath, (err) ->
					if err
						cb new IOError err
						return

					cb()
		], (err) ->
			if err
				cb err
				return

			# Dispatch event via event bus
			eventBus.trigger "createRevision:#{modelDef.name}", obj

			cb null, obj

	listRevisions = (contextualIds..., id, cb) ->
		if contextualIds.length isnt context.size
			cb new Error "wrong number of arguments"
			return

		fileNameEncryptionKey = getFileNameEncryptionKey()

		objDir = null
		revisions = null
		revObjs = null
		Async.series [
			(cb) ->
				lookupObjDirById contextualIds, id, (err, result) ->
					if err
						cb err
						return

					objDir = result

					cb()
			(cb) ->
				Fs.readdir objDir, (err, fileNames) ->
					if err
						cb new IOError err
						return

					revisions = Imm.List(fileNames)
					.filter (fileName) ->
						return not childCollectionNames.contains(fileName)
					.map (fileName) ->
						decryptedFileName = fileNameEncryptionKey.decrypt(
							Base64url.toBuffer fileName
						)
						revision = parseRevisionFileName(decryptedFileName)
							.set('_fileName', fileName)
							.set('_filePath', Path.join(objDir, fileName))
						return revision
					.sortBy (rev) -> Moment(rev.get('timestamp'), TimestampFormat)

					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, revisions

	readRevisions = (contextualIds..., id, cb) ->
		unless cb
			cb new Error "readRevisions must be provided a callback"
			return

		if contextualIds.length isnt context.size
			cb new Error "wrong number of arguments"
			return

		listRevisions contextualIds..., id, (err, revisions) ->
			if err
				cb err
				return

			Async.map revisions.toArray(), (rev, cb) ->
				readObjectFile rev.get('_filePath'), contextualIds, id, cb
			, (err, results) ->
				if err
					cb err
					return

				cb null, Imm.List(results)

	readLatestRevisions = (contextualIds..., id, maxRevisionCount, cb) ->
		unless cb
			throw new Error "readLatestRevisions must be provided a callback"

		if contextualIds.length isnt context.size
			cb new Error "wrong number of arguments"
			return

		if maxRevisionCount < 0
			cb new Error "maxRevisionCount must be >= 0"
			return

		# We could theoretically optimize for maxRevisionCount=0 here.
		# However, this would cause requests for non-existant objects to succeed.

		listRevisions contextualIds..., id, (err, revisions) ->
			if err
				cb err
				return

			# Only access the most recent revisions
			revisions = revisions.takeLast maxRevisionCount

			Async.map revisions.toArray(), (rev, cb) ->
				readObjectFile rev.get('_filePath'), contextualIds, id, cb
			, (err, results) ->
				if err
					cb err
					return

				cb null, Imm.List(results)

	# Private utility methods

	extractContextualIds = (obj) ->
		return context.map (contextEntry) ->
			contextDef = contextEntry.get('definition')
			contextIdProp = contextDef.name + 'Id'

			if obj.has(contextIdProp)
				return obj.get(contextIdProp)

			throw new Error "Object is missing field #{JSON.stringify contextIdProp}"

	getParentDir = (contextualIds, cb) ->
		if Array.isArray contextualIds
			contextualIds = Imm.List(contextualIds)

		if contextualIds.size is 0
			cb null, session.dataDirectory
			return

		parentApi = context.last().get('api')
		parentApi._lookupObjDirById contextualIds.skipLast(1), contextualIds.last(), cb

	lookupObjDirById = (contextualIds, objId, cb) ->
		if contextualIds instanceof Imm.List
			contextualIds = contextualIds.toArray()

		list contextualIds..., (err, objs) ->
			if err
				cb err
				return

			matches = objs.filter (obj) ->
				return obj.get('id') is objId

			if matches.size > 1
				cb new Error "multiple objects found with ID #{JSON.stringify objId}"
				return

			if matches.size < 1
				cb new ObjectNotFoundError()
				return

			match = matches.get(0)

			cb null, match.get('_dirPath')

	readObjectFile = (path, contextualIds, id, cb) ->
		schema = prepareSchema modelDef.schema, context

		Fs.readFile path, (err, encryptedObj) ->
			if err
				cb new IOError err
				return

			# Decrypt and parse JSON
			decryptedJson = session.globalEncryptionKey.decrypt encryptedObj
			obj = Imm.fromJS JSON.parse decryptedJson

			# Check that this object is where it should be
			# This is a security feature to prevent tampering
			Assert Imm.is(
				obj.get('_contextCollectionNames'),
				context.map(
					(c) -> c.get('definition').collectionName
				)
			), "found object of wrong type in collection #{modelDef.collectionName}"
			Assert Imm.is(
				obj.get('_contextIds'),
				Imm.fromJS(contextualIds)
			), "found object in wrong parent in collection #{modelDef.collectionName}"
			Assert Imm.is(
				obj.get('_collectionName'),
				modelDef.collectionName
			), "found an object from #{obj.get('_collectionName')} inside #{modelDef.collectionName}"
			Assert Imm.is(
				obj.get('id'),
				id
			), "object with ID=#{id} actually had ID=#{obj.get('id')}"
			obj = obj.delete('_contextCollectionNames')
				.delete('_contextIds')
				.delete('_collectionName')

			# Validate against the collection's schema
			validation = Joi.validate obj.toJS(), schema, joiValidationOptions

			if validation.error?
				cb validation.error
				return

			cb null, Imm.fromJS validation.value

	writeObjectFile = (obj, path, contextualIds, cb) ->
		schema = prepareSchema modelDef.schema, context

		# Validate against the collection's schema
		validation = Joi.validate obj.toJS(), schema, joiValidationOptions

		if validation.error?
			process.nextTick ->
				cb validation.error
			return

		# Specify where this object belongs
		# This is a security feature to prevent tampering
		validatedObjWithContext = Imm.fromJS(validation.value)
			.set('_contextCollectionNames', context.map(
				(c) -> c.get('definition').collectionName
			))
			.set('_contextIds', contextualIds)
			.set('_collectionName', modelDef.collectionName)
			.toJS()

		# Encode as JSON and encrypt
		objJson = JSON.stringify validatedObjWithContext
		encryptedObj = session.globalEncryptionKey.encrypt objJson

		Atomic.writeBufferToFile path, tmpDirPath, encryptedObj, (err) ->
			if err
				cb new IOError err
				return

			cb null, obj

	getFileNameEncryptionKey = ->
		return new Crypto.WeakSymmetricEncryptionKey(session.globalEncryptionKey, 5)

	result = {
		create,
		list,
		_lookupObjDirById: lookupObjDirById # private for internal use
	}

	if modelDef.isMutable
		result.createRevision = createRevision
		result.listRevisions = listRevisions
		result.readRevisions = readRevisions
		result.readLatestRevisions = readLatestRevisions
	else
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
	}

	# Each context type needs its own ID field
	context.forEach (contextEntry) ->
		typeName = contextEntry.get('definition').name
		newKeys[typeName + 'Id'] = IdSchema

	# Extend the original set of permissible keys
	return schema.keys(newKeys)

createObjectFileName = (obj, indexes) ->
	components = []

	for index in indexes
		indexValue = obj.getIn(index, '').toString()
		components.push new Buffer(indexValue, 'utf8')

	# ID is always indexed
	# For space efficiency, we'll take advantage of the fact that IDs are
	# essentially base64url.
	components.push Base64url.toBuffer obj.get('id')

	return encodeFileName components

parseRevisionFileName = (decryptedFileName) ->
	[timestamp, revisionId] = decodeFileName(decryptedFileName, 2)

	return Imm.Map({
		timestamp: timestamp.toString()
		revisionId: Base64url.encode revisionId
	})

createRevisionFileName = (obj) ->
	return encodeFileName [
		new Buffer(obj.get('timestamp'), 'utf8')
		Base64url.toBuffer obj.get('revisionId')
	]

# Since we want to include multiple strings in a single file name, an encoding
# is needed.  Ideally, we would use JSON, but JSON is rather verbose.  Since
# the file name will be encrypted, we're able to use arbitrary bytes.  We will
# use an encoding with the following rules:
# - The strings are first encoded as bytes as per UTF-8
# - All byte values (0x00 - 0xFF) except 0x00 are output unchanged.
# - 0x00 is encoded as 0x004C (i.e. a NUL byte followed by an ascii uppercase L).
#   "L" is a mnemonic for "Literal".
# - The encoded strings are delimited by 0x0053 (i.e. a NUL byte followed by an
#   ascii uppercase S).  "S" is a mnemonic for "Separator".
#
# This ensures that any string (or even any binary string) can be encoded and
# decoded unambiguously.

encodeFileName = (components) ->
	delimiter = new Buffer([0x00, 0x53])

	result = []

	for c, i in components
		if i > 0
			result.push delimiter

		encodedComp = encodeFileNameComponent(c)
		result.push encodedComp

	return Buffer.concat result

decodeFileName = (fileName, componentCount) ->
	comps = []

	nextComp = createZeroedBuffer(fileName.length)
	nextCompOffset = 0
	i = 0
	while i < fileName.length
		# If the next byte is a special sequence
		if fileName[i] is 0x00
			# If no more bytes in the file name
			if i is (fileName.length - 1)
				# There must always be another byte following a dot
				throw new Error "file name ended early: #{fileName.toJSON()}"

			switch fileName[i+1]
				when 0x4C # "L"
					# Add literal NUL byte to component
					nextComp[nextCompOffset] = 0x00
					nextCompOffset += 1
				when 0x53 # "S"
					# Found a separator, time to start on the next component

					# Add this component to result list
					comps.push nextComp.slice(0, nextCompOffset)

					# Reset for next component
					nextComp = createZeroedBuffer(fileName.length)
					nextCompOffset = 0
				else
					throw new Error "unexpected byte sequence at #{i} in file name: #{fileName.toJSON()}"

			# Skip over the next byte, since we already handled it
			i += 2
			continue

		nextComp[nextCompOffset] = fileName[i]
		nextCompOffset += 1

		i += 1

	# Add the last component to the result list
	comps.push nextComp.slice(0, nextCompOffset)

	if comps.length isnt componentCount
		console.log fileName
		throw new Error "expected #{componentCount} parts in file name #{JSON.stringify comps}"

	return comps

encodeFileNameComponent = (comp) ->
	unless Buffer.isBuffer comp
		throw new Error "expected file name component to be a buffer"

	literalNulByte = new Buffer([0x00, 0x4C])

	result = []

	for i in [0...comp.length]
		# If the byte needs to be encoded specially
		if comp[i] is 0x00
			result.push literalNulByte
			continue

		# This is probably pretty inefficient...
		result.push comp.slice(i, i+1)

	return Buffer.concat result

createZeroedBuffer = (bufferSize) ->
	result = new Buffer(bufferSize)

	for i in [0...bufferSize]
		result[i] = 0

	return result

module.exports = {
	createCollectionApi
}
