_ = require 'underscore'
Fs = require 'fs'
Joi = require 'joi'
Mkdirp = require 'mkdirp'
Path = require 'path'

ObjectHistory = require './objectHistory'

{IdSchema, ObjectNotFoundError, PathSafeString} = require './utils'

revisionSchema = Joi.object().keys({
	id: IdSchema
	revisionId: IdSchema
	timestamp: Joi.date().iso().raw() # TODO should be done through crypto
	name: Joi.string() # TODO this should be path safe...
	#name: PathSafeString
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

ensureObjectDirectory = (metric, cb) ->
	dirName = [
		metric.get('name')
		metric.get('id')
	].join '.'

	expectedPath = Path.join 'data', 'metrics', dirName

	_getObjectDirectory metric.get('id'), (err, actualPath) ->
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

		# It looks like the metric name changed
		Fs.rename actualPath, expectedPath, (err) ->
			if err
				cb err
				return

			cb null, expectedPath

readLatestRevisions = (metricId, limit, cb) ->
	_getObjectDirectory metricId, (err, objDir) ->
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

			global.EventBus.trigger 'newMetricRevision', result
			cb null, result

module.exports = {readLatestRevisions, createRevision}
