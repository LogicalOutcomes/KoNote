# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A file system (network drive) backend for persist.

Assert = require 'assert'
Async = require 'async'
Base64url = require 'base64url'
BufferEq = require 'buffer-equal-constant-time'
Fs = require 'graceful-fs'
Imm = require 'immutable'
Moment = require 'moment'
Path = require 'path'

Atomic = require '../atomic'
Cache = require '../cache'
Crypto = require '../crypto'

{
	IOError
	IdSchema
	ObjectNotFoundError
	TimestampFormat
	generateId
	extractContextualIds
} = require '../utils'

# Create a file system backend instance.
#
# eventBus: the EventBus to which object mutation events should be dispatched
# globalEncryptionKey: a SymmetricEncryptionKey for encrypting data objects
# dataDirectory: path to the directory where all application data should be stored
create = (eventBus, globalEncryptionKey, dataDirectory) ->
	# A directory for temp files, i.e. stuff we don't care about
	tmpDirPath = Path.join(dataDirectory, '_tmp')

	# A cache for remembering the results of list operations on this collection
	listCache = new Cache(5000) # 5-second expiry

	# Derive a (weak) encryption key to be used on file names.
	# File name encryption uses a different type of encryption key.
	# That key is generated here for convenience.
	#
	# The weak key is derived from globalEncryptionKey.
	# Security level 5 is used, i.e. 5 bytes of overhead
	# (see persist/crypto for details).
	fileNameEncryptionKey = new Crypto.WeakSymmetricEncryptionKey(globalEncryptionKey, 5)

	createObject = (obj, context, modelDef, cb) ->
		contextualIds = extractContextualIds obj, context

		destObjDir = null
		objDir = null
		objDirOp = null
		header = null

		Async.series [
			(cb) ->
				# Figure out what directory contains this collection.
				# This depends on whether this collection has a parent,
				# so pass in the contextualIds.
				getParentDir contextualIds, context, modelDef, (err, parentDir) ->
					if err
						cb err
						return

					# Generate this object's future directory name
					header = encodeObjectHeader(obj, modelDef.indexes)
					fileName = Base64url.encode fileNameEncryptionKey.encrypt header

					# Generate this object's future directory path
					destObjDir = Path.join(
						parentDir
						modelDef.collectionName
						fileName
					)

					cb()
			(cb) ->
				# In order to make the operation atomic, we write to a
				# temporary object directory first, then commit it later.
				Atomic.writeDirectory destObjDir, tmpDirPath, (err, tmpObjDir, op) ->
					if err
						cb err
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
				# Create the first revision of this new object

				# Generate the revision file name and path
				revHeader = encodeObjectRevisionHeader(obj)
				revFileName = Base64url.encode fileNameEncryptionKey.encrypt revHeader

				# The revision file will go in the object directory
				revFilePath = Path.join(objDir, revFileName)

				writeObjectRevisionFile obj, revFilePath, contextualIds, context, modelDef, cb
			(cb) ->
				# Done preparing the object directory, finish the operation atomically
				objDirOp.commit cb
		], (err) ->
			if err
				cb err
				return

			# Update list cache to include new object
			listCache.update getListCacheKey(contextualIds, context, modelDef), (oldHeaders) ->
				# Add header of this new object to cached list
				return oldHeaders.push decodeObjectHeader(header, modelDef.indexes, destObjDir)

			# Dispatch event via event bus, notifying the app of the change
			eventBus.trigger "create:#{modelDef.name}", obj

			cb()

	listObjectsInCollection = (contextualIds, context, modelDef, cb) ->
		# Check cache
		cacheKey = getListCacheKey(contextualIds, context, modelDef)
		cachedResult = listCache.get(cacheKey)
		if cachedResult?
			cb null, cachedResult
			return

		collectionDir = null
		fileNames = null

		Async.series [
			(cb) ->
				# Get path to directory that contains this collection
				getParentDir contextualIds, context, modelDef, (err, parentDir) ->
					if err
						cb err
						return

					collectionDir = Path.join(
						parentDir
						modelDef.collectionName
					)
					cb()
			(cb) ->
				# Each file in the collection dir is an object
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

			# Decrypt/parse the file names
			headers = Imm.List(fileNames)
				.filter isValidFileName
				.map (fileName) ->
					# Decrypt file name
					decryptedFileName = fileNameEncryptionKey.decrypt(
						Base64url.toBuffer fileName
					)

					# Parse file name
					return decodeObjectHeader(
						decryptedFileName, modelDef.indexes,
						Path.join(collectionDir, fileName)
					)

			# Store result in cache
			listCache.set(cacheKey, headers)

			cb null, headers

	readObject = (contextualIds, id, context, modelDef, cb) ->
		# Get the path of the object directory corresponding to this ID
		lookupObjDirById contextualIds, id, context, modelDef, (err, objDir) ->
			if err
				cb err
				return

			# List the directory to see all revisions
			Fs.readdir objDir, (err, revisionFiles) ->
				if err
					cb new IOError err
					return

				# Object directories can also contain other collections,
				# so we need to filter those out first
				# Ensure validFileName first
				revisionFiles = revisionFiles.filter (fileName) ->
					return isValidFileName(fileName) and not modelHasChild(modelDef, fileName)

				# The read method is only available to immutable collections
				if revisionFiles.length > 1
					cb new Error "object at #{JSON.stringify objDir} is immutable but has multiple revisions"
					return

				# There should always be exactly one revision
				if revisionFiles.length < 1
					# This should be impossible, because object creation is
					# implemented atomically.  If this occurs, it is likely due
					# to a failed migration.
					cb new Error "missing revisions in #{JSON.stringify objDir}"
					return

				# Get the only revision of this object
				revisionFile = revisionFiles[0]
				revisionFilePath = Path.join(objDir, revisionFile)

				# Read the only revision
				readObjectRevisionFile revisionFilePath, contextualIds, id, context, modelDef, cb

	createObjectRevision = (obj, context, modelDef, cb) ->
		objId = obj.get('id')
		contextualIds = extractContextualIds obj, context

		objDir = null

		Async.series [
			(cb) ->
				# Find where this object's directory is located
				lookupObjDirById contextualIds, objId, context, modelDef, (err, result) ->
					if err
						cb err
						return

					objDir = result
					cb()
			(cb) ->
				# Determine file name and path for this revision
				revHeader = encodeObjectRevisionHeader(obj)
				revFileName = Base64url.encode fileNameEncryptionKey.encrypt revHeader
				revFilePath = Path.join(objDir, revFileName)

				# Write the revision to a file
				writeObjectRevisionFile obj, revFilePath, contextualIds, context, modelDef, cb
			(cb) ->
				# When an indexed property changes, we need to rename the object directory
				# so that the change shows up when `list()` is used.

				parentDirPath = Path.dirname objDir

				# This is what the object header should be when we're done.
				expectedHeader = encodeObjectHeader(obj, modelDef.indexes)

				# Decrypt the current header
				currentDirName = Path.basename objDir
				currentHeader = fileNameEncryptionKey.decrypt(
					Base64url.toBuffer currentDirName
				)

				# Does the current header match what we want?
				if BufferEq(expectedHeader, currentHeader)
					# OK, no update needed
					cb()
					return

				# Expectations didn't meet reality, so we gotta fix it.

				# Take the expected header, encrypt it
				currentDirPath = Path.join(parentDirPath, currentDirName)
				newDirName = Base64url.encode fileNameEncryptionKey.encrypt expectedHeader
				newDirPath = Path.join(parentDirPath, newDirName)

				# Rename the object directory to the new encrypted name
				objDir = newDirPath
				Fs.rename currentDirPath, newDirPath, (err) ->
					if err
						cb new IOError err
						return

					# Update list cache to reflect new objDir name
					listCache.update getListCacheKey(contextualIds, context, modelDef), (oldHeaders) ->
						return oldHeaders.map (oldHeader) ->
							if oldHeader.get('id') != objId
								return oldHeader

							# Replace this old header with the new updated header
							return decodeObjectHeader(expectedHeader, modelDef.indexes, objDir)

					cb()
		], (err) ->
			if err
				cb err
				return

			# Dispatch event via event bus to notify the rest of the app
			# about the change
			eventBus.trigger "createRevision:#{modelDef.name}", obj

			cb()

	listObjectRevisions = (contextualIds, id, context, modelDef, cb) ->
		objDir = null
		revisions = null
		revObjs = null

		Async.series [
			(cb) ->
				# Locate the object's directory
				lookupObjDirById contextualIds, id, context, modelDef, (err, result) ->
					if err
						cb err
						return

					objDir = result
					cb()
			(cb) ->
				# List the revision files inside the object dir
				Fs.readdir objDir, (err, fileNames) ->
					if err
						cb new IOError err
						return

					revisions = Imm.List(fileNames)
					.filter (fileName) ->
						# Object directories can also contain child collections.
						# These need to be filtered out.
						# Ensure validFileName first
						return isValidFileName(fileName) and not modelHasChild(modelDef, fileName)
					.map (fileName) ->
						# Decrypt the revision header
						encodedRevisionHeader = fileNameEncryptionKey.decrypt(
							Base64url.toBuffer fileName
						)

						# Parse the revision header
						revisionHeader = decodeObjectRevisionHeader(encodedRevisionHeader)

						# Add fields for internal use
						return revisionHeader.set('_filePath', Path.join(objDir, fileName))
					# Sort the results from earliest to latest
					.sortBy (rev) -> Moment(rev.get('timestamp'), TimestampFormat)

					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, revisions

	readObjectRevision = (contextualIds, id, revisionId, context, modelDef, cb) ->
		listObjectRevisions contextualIds, id, context, modelDef, (err, revs) ->
			if err
				cb err
				return

			revsWithId = revs.filter (rev) ->
				return rev.get('revisionId') is revisionId

			if revsWithId.size is 0
				cb new ObjectNotFoundError()
				return

			if revsWithId.size > 1
				# This should never happen.
				# If it does happen, it is probably due to a problem with a
				# migration.
				cb new Error("found multiple revisions with ID " + revisionId)
				return

			rev = revsWithId.first()
			readObjectRevisionFile rev.get('_filePath'), contextualIds, id, context, modelDef, cb

	# Private utility methods

	getListCacheKey = (contextualIds, context, modelDef) ->
		# IDs and collection names never contain colons
		return [modelDef.collectionName].concat(contextualIds.toArray()).join('::')

	# Get the path to the parent object's directory.
	# If this collection does not have a parent object, just returns the data
	# directory path.
	getParentDir = (contextualIds, context, modelDef, cb) ->
		# If this collection is not a child of some object
		if contextualIds.size is 0
			# The parent directory is just the data directory
			cb null, dataDirectory
			return

		# Get context and data model definition for the parent collection
		parentContext = context.skipLast(1)
		parentModelDef = context.last()

		# Look up the parent object directory in the parent collection
		lookupObjDirById contextualIds.skipLast(1), contextualIds.last(), parentContext, parentModelDef, cb

	# Get the path to the directory of an object in this collection.
	lookupObjDirById = (contextualIds, objId, context, modelDef, cb) ->
		# List all objects in this collection
		listObjectsInCollection contextualIds, context, modelDef, (err, objs) ->
			if err
				cb err
				return

			# Find the object we're looking for
			matches = objs.filter (obj) ->
				return obj.get('id') is objId

			if matches.size > 1
				cb new Error "multiple objects found with ID #{JSON.stringify objId}"
				return

			if matches.size < 1
				cb new ObjectNotFoundError()
				return

			# Get the only match
			match = matches.get(0)

			# Return the object directory path
			cb null, match.get('_dirPath')

	# Read the object revision file at the specified path.
	#
	# This function decrypts the object data, parses the JSON, and validates
	# the object against the collection schema.  The object's ID and context
	# fields are also validated for security purposes.
	readObjectRevisionFile = (path, contextualIds, id, context, modelDef, cb) ->
		Fs.readFile path, (err, encryptedObj) ->
			if err
				cb new IOError err
				return

			# Decrypt and parse JSON
			decryptedJson = globalEncryptionKey.decrypt encryptedObj
			obj = Imm.fromJS JSON.parse decryptedJson

			# Check that this object is where it should be
			# This is a security feature to prevent tampering
			Assert Imm.is(
				obj.get('_contextCollectionNames'),
				context.map(
					(c) -> c.collectionName
				)
			), "found object of wrong type in collection #{modelDef.collectionName}"
			Assert Imm.is(
				obj.get('_contextIds'),
				contextualIds
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

			cb null, obj

	# Write an object revision file to the specified path.
	#
	# This function will encode and encrypt the object.  Before doing so,
	# however, it will add information about the object's context, and validate
	# the object against this collection's schema.
	writeObjectRevisionFile = (obj, path, contextualIds, context, modelDef, cb) ->
		# Specify where this object belongs
		# This is a security feature to prevent tampering
		objWithContext = obj
			.set('_contextCollectionNames', context.map(
				(c) -> c.collectionName
			))
			.set('_contextIds', contextualIds)
			.set('_collectionName', modelDef.collectionName)
			.toJS()

		# Encode as JSON and encrypt
		objJson = JSON.stringify objWithContext
		encryptedObj = globalEncryptionKey.encrypt objJson

		# Write the encrypted object to the specified path
		# Use an atomic operation to prevent files from being partially written
		# (or corrupted).
		Atomic.writeBufferToFile path, tmpDirPath, encryptedObj, (err) ->
			if err
				cb err
				return

			cb null, obj

	modelHasChild = (modelDef, childCollectionName) ->
		modelDef.children.some (childModelDef) ->
			return childModelDef.collectionName is childCollectionName

	return {
		createObject
		listObjectsInCollection
		readObject
		createObjectRevision
		listObjectRevisions
		readObjectRevision
	}

encodeObjectHeader = (obj, indexes) ->
	components = []

	for index in indexes
		indexValue = obj.getIn(index, '').toString()
		components.push Buffer.from(indexValue, 'utf8')

	# ID is always indexed
	# For space efficiency, we'll take advantage of the fact that IDs are
	# essentially base64url.
	components.push Base64url.toBuffer obj.get('id')

	return encodeHeader components

decodeObjectHeader = (header, indexes, dirPath) ->
	[indexValues..., id] = decodeHeader(header, indexes.length + 1, dirPath)

	result = Imm.Map({
		id: Base64url.encode id
		_dirPath: dirPath # for internal use only
	})

	# Use model def to match up the indexed field names with their values
	for indexedProp, i in indexes
		result = result.setIn indexedProp, indexValues[i].toString()

	return result

encodeObjectRevisionHeader = (obj) ->
	return encodeHeader [
		Buffer.from(obj.get('timestamp'), 'utf8')
		Base64url.toBuffer obj.get('revisionId') # decode revision ID to save space
	]

decodeObjectRevisionHeader = (header) ->
	# Object revision headers are encoded the same as object headers.
	# The difference is that revision headers are always just
	# timestamp+revisionId, instead of having a variable number of index
	# fields.  More precisely, revision headers always have exactly two
	# components: a timestamp and a revision ID.
	[timestamp, revisionId] = decodeHeader(header, 2, 'revisionHeader')

	return Imm.Map({
		timestamp: timestamp.toString()
		revisionId: Base64url.encode revisionId
	})

# File names are used to store object and revision headers for efficient
# retrieval.  Since a header consists of multiple strings, an encoding is
# needed to fit them all into a single file name.  Ideally, we would use JSON,
# but JSON is rather verbose.  Since the header will be encrypted, we're able
# to use arbitrary bytes.  We will use an encoding with the following rules:
# - The strings are first encoded as bytes as per UTF-8
# - All byte values (0x00 - 0xFF) except 0x00 are output unchanged.
# - 0x00 is encoded as 0x004C (i.e. a NUL byte followed by an ascii uppercase L).
#   "L" is a mnemonic for "Literal".
# - The encoded strings are delimited by 0x0053 (i.e. a NUL byte followed by an
#   ascii uppercase S).  "S" is a mnemonic for "Separator".
#
# This ensures that any string (or even any binary string) can be encoded and
# decoded unambiguously.

encodeHeader = (components) ->
	delimiter = Buffer.from([0x00, 0x53])

	result = []

	for c, i in components
		if i > 0
			result.push delimiter

		encodedComp = encodeHeaderComponent(c)
		result.push encodedComp

	return Buffer.concat result

decodeHeader = (header, componentCount, parentName) ->
	comps = []

	nextComp = Buffer.alloc(header.length)
	nextCompOffset = 0
	i = 0
	while i < header.length
		# If the next byte is a special sequence
		if header[i] is 0x00
			# If no more bytes in the header
			if i is (header.length - 1)
				# There must always be another byte following a dot
				throw new Error "header ended early: #{header.toJSON()}"

			switch header[i+1]
				when 0x4C # "L"
					# Add literal NUL byte to component
					nextComp[nextCompOffset] = 0x00
					nextCompOffset += 1
				when 0x53 # "S"
					# Found a separator, time to start on the next component

					# Add this component to result list
					comps.push nextComp.slice(0, nextCompOffset)

					# Reset for next component
					nextComp = Buffer.alloc(header.length)
					nextCompOffset = 0
				else
					throw new Error "unexpected byte sequence at #{i} in header: #{header.toJSON()}"

			# Skip over the next byte, since we already handled it
			i += 2
			continue

		nextComp[nextCompOffset] = header[i]
		nextCompOffset += 1

		i += 1

	# Add the last component to the result list
	comps.push nextComp.slice(0, nextCompOffset)

	if comps.length isnt componentCount
		console.log header
		throw new Error "expected #{componentCount} parts in #{parentName} header indexes #{JSON.stringify comps}"

	return comps

# In order to support arbitrary binary strings, this method encodes 0x00 bytes
# as 0x004C.
encodeHeaderComponent = (comp) ->
	unless Buffer.isBuffer comp
		throw new Error "expected header component to be a buffer"

	literalNulByte = Buffer.from([0x00, 0x4C])

	result = []

	for i in [0...comp.length]
		# If the byte needs to be encoded specially
		if comp[i] is 0x00
			result.push literalNulByte
			continue

		# This is probably pretty inefficient...
		result.push comp.slice(i, i+1)

	return Buffer.concat result

# Check fileName against OS metadata files
isValidFileName = (fileName) ->
	return fileName not in ['.DS_Store', 'Thumbs.db']

# A convenience method.  Creates a Buffer filled with 0x00 bytes.
#
# When a Buffer is first created, its contents are leftover from whatever used
# that area of memory last, which might mean that it contains sensitive
# information.  By zeroing Buffers before use, we avoid that security risk.
# not required for nwjs >= v0.23.0 (buffers are zeroed by default in node8)
# preserved here only for compatibility with old migration files
createZeroedBuffer = (bufferSize) ->
	result = new Buffer(bufferSize)
	result.fill(0)
	return result

module.exports = {create}
