# The data structure that stores information about one particular client.
# This includes all of that client's progress notes.
#
# TODO current crypto plans:
#  - each object has ID, verified to match file or folder name (always verify context)
#  - each object is signed
#  - if object has revision history, one rev/file, all in one folder
#  - timestamps are verified via a global timestamp hash chain (accurate +/- 2 hours)

_ = require 'underscore'
Fs = require 'fs'
Imm = require 'immutable'
Joi = require 'joi'
Path = require 'path'

ObjectUtils = require './object'
ObjectHistory = require './objectHistory'

{IdSchema, PathSafeString, ObjectNotFoundError, validateClientName} = require './utils'

revisionSchema = Joi.object().keys({
	clientId: IdSchema
	revisionId: IdSchema
	timestamp: Joi.date().iso().raw() # TODO should be done through crypto
	clientName: Joi.object().keys({
		first: PathSafeString
		middle: PathSafeString
		last: PathSafeString
	})
	plan: Joi.object().keys({
		sections: Joi.array().includes(
			Joi.object().keys({
				id: IdSchema
				name: Joi.string()
				targetIds: Joi.array().includes(
					IdSchema
				)
			})
		)
	})
})

ensureObjectDirectory = (clientFile, cb) ->
	validateClientName clientFile.get('clientName')

	dirName = [
		clientFile.get('clientName').get('first')
		clientFile.get('clientName').get('last')
		clientFile.get('clientId')
	].join '.'

	expectedPath = Path.join 'data', 'clientFiles', dirName

	_getObjectDirectory clientFile.get('clientId'), (err, actualPath) ->
		if err
			if err instanceof ObjectNotFoundError
				# New object, just create the dir and return
				Mkdirp expectedPath, (err) ->
					if err
						cb err
						return

					cb null, expectedPath
				return

			cb err
			return

		if actualPath is expectedPath
			# Everything's good!
			cb null, actualPath
			return

		# It looks like the client name changed
		Fs.rename actualPath, expectedPath, (err) ->
			if err
				cb err
				return

			cb null, expectedPath

parseDirectoryName = (dirName) ->
	[firstName, lastName, clientId] = dirName.split '.'

	return Imm.fromJS {
		name: {
			first: firstName
			last: lastName
		}
		clientId
	}

_getObjectDirectory = (clientId, cb) ->
	clientFilesDir = Path.join('data', 'clientFiles')
	Fs.readdir clientFilesDir, (err, clientFileNames) ->
		if err
			cb err
			return

		clientFileName = _.find clientFileNames, (f) ->
			return f.endsWith('.' + clientId)

		unless clientFileName
			cb new ObjectNotFoundError "no client file for client with ID #{JSON.stringify clientId}"
			return

		cb null, Path.join(clientFilesDir, clientFileName)

readLatestRevisions = (clientId, limit, cb) ->
	_getObjectDirectory clientId, (err, objDir) ->
		if err
			cb err
			return

		ObjectHistory.readLatestRevisions objDir, revisionSchema, limit, cb

createRevision = (newRevision, cb) ->
	ensureObjectDirectory newRevision, (err, objDir) ->
		if err
			cb err
			return

		ObjectHistory.createRevision newRevision, objDir, revisionSchema, (err, result) ->
			if err
				cb err
				return

			global.EventBus.trigger 'newClientFileRevision', result
			cb null, result

list = (cb) ->
	clientFilesDir = Path.join 'data', 'clientFiles'
	Fs.readdir clientFilesDir, (err, files) ->
		if err
			if err.code is 'ENOENT'
				cb null, Imm.List()
				return

			cb err
			return

		cb null, Imm.fromJS(files).map(parseDirectoryName)

module.exports = {readLatestRevisions, createRevision, list, _getObjectDirectory}
