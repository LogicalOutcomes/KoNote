Joi = require 'joi'
Path = require 'path'

ObjectHistory = require './objectHistory'

{IdSchema} = require './utils'

revisionSchema = Joi.object().keys({
	id: IdSchema
	timestamp: Joi.date().iso().raw() # TODO should be done through crypto
	name: Joi.string()
	definition: Joi.string()
})

_getObjectDirectory = (metricId, cb) ->
	metricsDir = Path.join 'data', 'metrics'
	Fs.readdir metricsDir, (err, metricFileNames) ->
		if err
			cb err
			return

		metricFileName = _.find metricFileNames, (f) ->
			return f.endsWith('.' + metricId)

		unless metricFileName
			cb new ObjectNotFoundError "no metric with ID #{JSON.stringify metricId}"
			return

		cb null, Path.join(metricsDir, metricFileName)

readRevisions = (metricId, cb) ->
	_getObjectDirectory metricId, (err, objDir) ->
		if err
			cb err
			return

		ObjectHistory.readRevisions objDir, revisionSchema, cb

createRevision = (newRevision, cb) ->
	_getObjectDirectory newRevision.get('id'), (err, objDir) ->
		if err
			cb err
			return

		ObjectHistory.createRevision newRevision, objDir, revisionSchema, (err, result) ->
			if err
				cb err
				return

			global.EventBus.trigger 'newMetricRevision', result
			cb null, result

module.exports = {readRevisions, createRevision}
