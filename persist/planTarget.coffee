Async = require 'async'
Imm = require 'immutable'
Joi = require 'joi'
Path = require 'path'

ClientFile = require './clientFile'
ObjectHistory = require './objectHistory'

{IdSchema} = require './utils'

revisionSchema = Joi.object().keys({
	id: IdSchema
	revisionId: IdSchema
	clientId: IdSchema
	author: Joi.string() # TODO should be done through crypto
	timestamp: Joi.date().iso().raw() # TODO should be done through crypto
	name: Joi.string()
	notes: Joi.string()
	metricIds: Joi.array().items(
		IdSchema
	)
})

_getObjectDirectory = (clientId, planTargetId, cb) ->
	ClientFile._getObjectDirectory clientId, (err, clientFilePath) ->
		if err
			cb err
			return

		cb null, Path.join clientFilePath, 'planTargets', planTargetId

readRevisions = (clientId, planTargetId, cb) ->
	_getObjectDirectory clientId, planTargetId, (err, objDir) ->
		if err
			cb err
			return

		ObjectHistory.readRevisions objDir, revisionSchema, cb

createRevision = (newRevision, cb) ->
	_getObjectDirectory newRevision.get('clientId'), newRevision.get('id'), (err, objDir) ->
		if err
			cb err
			return

		ObjectHistory.createRevision newRevision, objDir, revisionSchema, (err, result) ->
			if err
				cb err
				return

			global.EventBus.trigger 'newPlanTargetRevision', result
			cb null, result

readClientFileTargets = (clientFile, cb) ->
	targetIds = []

	clientFile.getIn(['plan', 'sections']).forEach (section) =>
		section.get('targetIds').forEach (targetId) =>
			targetIds.push targetId

	Async.map targetIds, (targetId, cb) ->
		readRevisions clientFile.get('clientId'), targetId, (err, revs) ->
			if err
				cb err
				return

			result = {
				id: targetId
				revisions: revs
			}
			cb null, result
	, (err, targets) ->
		if err
			cb err
			return

		cb null, Imm.Map(Imm.fromJS(targetIds).zip(Imm.fromJS(targets)))

module.exports = {readRevisions, createRevision, readClientFileTargets}
