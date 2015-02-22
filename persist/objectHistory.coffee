Async = require 'async'
Fs = require 'fs'
Imm = require 'immutable'
Mkdirp = require 'mkdirp'
Moment = require 'moment'
Path = require 'path'

{generateId, SafeTimestampFormat, validate} = require './utils'

parseRevisionFileName = (revFileName) ->
	[timestamp, revisionId] = revFileName.split '.'
	return {
		timestamp: Moment(timestamp, SafeTimestampFormat)
		revisionId
		fileName: revFileName
	}

createRevisionFileName = (timestamp, revisionId) ->
	return "#{Moment(timestamp).format(SafeTimestampFormat)}.#{revisionId}"

readRevisions = (objectDirPath, revisionSchema, cb) ->
	revisionsDir = Path.join objectDirPath, 'revisions'
	Fs.readdir revisionsDir, (err, revFileNames) ->
		if err
			cb err
			return

		revFileNames = Imm.fromJS(revFileNames)
		.map(parseRevisionFileName)
		.sortBy (rev) -> -rev.timestamp # sort newest first
		.map (rev) -> rev.fileName
		.toJS()

		Async.map revFileNames, (revFileName, cb) ->
			# TODO validate context, timestamp, signatures...
			Fs.readFile Path.join(revisionsDir, revFileName), (err, buf) ->
				if err
					cb err
					return

				parsed = JSON.parse buf
				validate parsed, revisionSchema, (err, parsed) ->
					if err
						cb err
						return

					cb null, Imm.fromJS parsed
		, (err, results) ->
			if err
				cb err
				return

			cb null, Imm.fromJS results

readLatestRevisions = (objectDirPath, revisionSchema, limit, cb) ->
	revisionsDir = Path.join objectDirPath, 'revisions'

	Fs.readdir revisionsDir, (err, revFileNames) ->
		if err
			cb err
			return

		latestRevFileNames = Imm.fromJS(revFileNames)
		.map(parseRevisionFileName)
		.sortBy (rev) -> -rev.timestamp # sort newest first
		.map (rev) -> rev.fileName
		.take(limit)
		.toJS()

		Async.map latestRevFileNames, (revFileName, cb) ->
			# TODO validate context, timestamp, signatures...
			Fs.readFile Path.join(revisionsDir, revFileName), (err, buf) ->
				if err
					cb err
					return

				parsed = JSON.parse buf
				validate parsed, revisionSchema, (err) ->
					if err
						cb err
						return

					cb null, Imm.fromJS(parsed)
		, cb

createRevision = (newRevision, objectDirPath, revisionSchema, cb) ->
	revId = generateId()
	newRevision = newRevision.set 'revisionId', revId

	newRevision = newRevision.set 'timestamp', Moment().format()

	revAsJs = newRevision.toJS()

	validate revAsJs, revisionSchema, (err, revAsJs) ->
		if err
			cb err
			return

		revisionsDir = Path.join objectDirPath, 'revisions'
		Mkdirp revisionsDir, (err) ->
			if err
				cb err
				return

			revisionFileName = createRevisionFileName(
				revAsJs.timestamp
				revAsJs.revisionId
			)
			revisionPath = Path.join revisionsDir, revisionFileName
			Fs.writeFile revisionPath, JSON.stringify(revAsJs), (err) ->
				if err
					cb err
					return

				cb null, Imm.fromJS revAsJs

module.exports = {readRevisions, readLatestRevisions, createRevision}
