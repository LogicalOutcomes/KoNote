Async = require 'async'
Fs = require 'fs'
Joi = require 'joi'
Imm = require 'immutable'
Moment = require 'moment'
Path = require 'path'

{
	IOError
	IdSchema
	ObjectNotFoundError
	TimestampFormat
	generateId
} = require './utils'

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

		objDir = null

		Async.series [
			(cb) ->
				getParentDir contextualIds, (err, parentDir) ->
					if err
						cb err
						return

					objDir = Path.join(
						parentDir
						modelDef.collectionName
						createObjectFileName(obj, modelDef.indexes)
					)
					cb()
			(cb) ->
				Fs.mkdir objDir, (err) ->
					if err
						cb new IOError err
						return

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
				revFile = Path.join(objDir, createRevisionFileName(obj))
				writeObjectFile obj, revFile, cb
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
					[indexValues..., id] = decodeFileName(fileName, modelDef.indexes.length + 1)

					result = Imm.Map({id, _dirPath: Path.join(collectionDir, fileName)})

					for indexedProp, i in modelDef.indexes
						result = result.setIn indexedProp, indexValues[i]

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

				readObjectFile revisionFilePath, cb

	createRevision = (obj, cb) ->
		unless obj.has('id')
			cb new Error "missing property 'id'"
			return

		contextualIds = extractContextualIds obj

		obj = obj
		.set 'revisionId', generateId()
		.set 'author', session.userName
		.set 'timestamp', Moment().format(TimestampFormat)

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
				# When an indexed property changes, we need to rename the dir
				expectedDirName = createObjectFileName(obj, modelDef.indexes)
				actualDirName = Path.basename objDir
				parentDirPath = Path.dirname objDir

				if expectedDirName is actualDirName
					cb()
					return

				# But sometimes expectations don't meet reality
				actualDirPath = Path.join(parentDirPath, actualDirName)
				expectedDirPath = Path.join(parentDirPath, expectedDirName)

				objDir = expectedDirPath
				Fs.rename actualDirPath, expectedDirPath, (err) ->
					if err
						cb new IOError err
						return

					cb()
			(cb) ->
				revFile = Path.join(objDir, createRevisionFileName(obj))
				writeObjectFile obj, revFile, cb
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
					.map(parseRevisionFileName)
					.map (rev) ->
						return rev.set '_filePath', Path.join(
							objDir
							rev.get('_fileName')
						)
					.sortBy (rev) -> Moment(rev.timestamp, TimestampFormat)

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
				readObjectFile rev.get('_filePath'), cb
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
				readObjectFile rev.get('_filePath'), cb
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

	readObjectFile = (path, cb) ->
		schema = prepareSchema modelDef.schema, context

		Fs.readFile path, (err, encryptedObj) ->
			if err
				cb new IOError err
				return

			decryptedJson = session.globalEncryptionKey.decrypt encryptedObj
			obj = JSON.parse decryptedJson

			validation = Joi.validate obj, schema

			if validation.error?
				cb validation.error
				return

			cb null, Imm.fromJS validation.value

	writeObjectFile = (obj, path, cb) ->
		schema = prepareSchema modelDef.schema, context

		validation = Joi.validate obj.toJS(), schema

		if validation.error?
			process.nextTick ->
				cb validation.error
			return

		objJson = JSON.stringify validation.value
		encryptedObj = session.globalEncryptionKey.encrypt objJson

		Fs.writeFile path, encryptedObj, (err) ->
			if err
				cb new IOError err
				return

			cb null, obj

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
		components.push indexValue

	# ID is always indexed
	components.push obj.get('id')

	return encodeFileName components

parseRevisionFileName = (revFileName) ->
	[timestamp, revisionId] = decodeFileName(revFileName, 2)

	return Imm.Map({timestamp, revisionId, _fileName: revFileName})

createRevisionFileName = (obj) ->
	return encodeFileName [
		obj.get('timestamp')
		obj.get('revisionId')
	]

encodeFileName = (components) ->
	return (encodeFileNameComponent(c) for c in components).join('.')

decodeFileName = (fileName, componentCount) ->
	comps = fileName.split('.')

	if comps.length isnt componentCount
		throw new Error "expected #{componentCount} parts in file name #{JSON.stringify fileName}"

	return (decodeFileNameComponent(c) for c in comps)

# Windows is super strict about file names, so we need to encode things aggressively.
encodeFileNameComponent = (s) ->
	# Percent encode all character except for a few safe characters
	return s.replace /[^a-zA-Z0-9 $#&_\-]/g, (c) ->
		charInHex = c.charCodeAt(0).toString(16)

		if charInHex.length is 1
			return '%0' + charInHex

		if charInHex.length is 2
			return '%' + charInHex

		if charInHex.length is 3
			return '%%0' + charInHex

		if charInHex.length is 4
			return '%%' + charInHex

		throw new Error "unexpected character: \\u#{charInHex}"

decodeFileNameComponent = (s) ->
	s = s.replace /%%([a-fA-F0-9]{4})/g, (match, hex) ->
		return String.fromCharCode parseInt(hex, 16)
	s = s.replace /%([a-fA-F0-9]{2})/g, (match, hex) ->
		return String.fromCharCode parseInt(hex, 16)
	return s


module.exports = {
	createCollectionApi
}
