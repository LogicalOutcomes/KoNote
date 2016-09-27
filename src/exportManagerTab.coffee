# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
_ = require 'underscore'
Imm = require 'immutable'
Persist = require './persist'
Fs = require 'graceful-fs'
Path = require 'path'
Term = require './term'
Archiver = require 'archiver'
CSVConverter = require 'json-2-csv'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Moment = require 'moment'

	Config = require('./config')
	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)
	{handleCustomError, FaIcon, renderName, showWhen} = require('./utils').load(win)
	{TimestampFormat} = require('./persist/utils')

	ExportManagerTab = React.createFactory React.createClass
		displayName: 'ExportManagerTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				progress: 0
				message: null
				isLoading: null
				exportProgress: {
					percent: null
					message: null
				}
			}

		render: ->
			return R.div({className: 'exportManagerTab'},
				R.div({className: 'header'},
					R.h1({}, "Export Data")
				)
				R.div({className: 'main'},
					Spinner {
						isVisible: @state.isLoading
						isOverlay: true
						message: @state.exportProgress.message
						percent: @state.exportProgress.percent
					}
					# Hidden input for handling file saving
					R.input({
						ref: 'nwsaveas'
						className: 'hidden'
						type: 'file'
					})

					R.button({
						className: 'btn btn-default btn-lg'
						onClick: @_export.bind null, {
							defaultName: "konote-metrics"
							extension: 'csv'
							runExport: @_saveMetrics
						}
					}, "Export #{Term 'Metrics'} to CSV")
					R.button({
						className: 'btn btn-default btn-lg'
						onClick: @_export.bind null, {
							defaultName: "konote-events"
							extension: 'csv'
							runExport: @_saveEvents
						}
					}, "Export #{Term 'Events'} to CSV")
					R.button({
						className: 'btn btn-default btn-lg'
						onClick: @_export.bind null, {
							defaultName: "konote-backup"
							extension: 'zip'
							runExport: @_saveBackup
						}
					}, "Backup All Data to ZIP")
				)
			)

		_prettySize: (bytes) ->
			if bytes / 1024 > 1024
				return (bytes/1024/1024).toFixed(2) + "MB"
			return (bytes/1024).toFixed(0) + "KB"

		_updateProgress: (percent, message) ->
			if not percent and not message
				percent = message = null

			@setState {
				isLoading: true
				exportProgress: {
					percent
					message: message or @state.exportProgress.message
				}
			}


		_export: ({defaultName, extension, runExport}) ->
			timestamp = Moment().format('YYYY-MM-DD')
			# Configures hidden file inputs with custom attributes, and clicks it
			$nwsaveasInput = $(@refs.nwsaveas)

			$nwsaveasInput
			.off()
			.val('')
			.attr('nwsaveas', "#{defaultName}-#{timestamp}")
			.attr('accept', ".#{extension}")
			.on('change', (event) => runExport event.target.value)
			.click()

		_saveEvents: (path) ->
			isConfirmClosed = false
			# Map over client files

			console.log "clientfileheaders: ", @props.clientFileHeaders.toArray()

			if @props.clientFileHeaders.size is 0
				Bootbox.alert {
					title: "No #{Term 'Events'} to Export"
					message: "You must create at least one client file with events before they can be exported!"
				}
			else
				@_updateProgress 0, "Saving #{Term 'Events'} to CSV..."
				console.log "progress should be 0"
				console.log "size of clients array: ", @props.clientFileHeaders.size
				progressIterator = 0

				Async.map @props.clientFileHeaders.toArray(), (clientFile, cb) =>
					progEventsHeaders = null
					progEvents = null
					progEventsList = null
					clientFileId = clientFile.get('id')
					clientName = renderName clientFile.get('clientName')
					clientFileProgramLinkIds = null
					programHeaders = null
					programs = @props.programs
					programNames = null
					csv = null
					progressIterator = progressIterator + 1


					console.log "checking clientFile with name: ",  clientName, progressIterator
					currentProgress = (progressIterator/@props.clientFileHeaders.size) * 90
					@_updateProgress currentProgress

					Async.series [
						# get clientfile program links
						(cb) =>
							clientFileProgramLinkIds = @props.clientFileProgramLinks
							.filter (link) ->
								link.get('clientFileId') is clientFileId and
								link.get('status') is "enrolled"
							.map (link) ->
								link.get('programId')

							console.log "link IDs: ", clientFileProgramLinkIds.toJS()

							cb()

						(cb) =>
							programNames = programs
							.filter (program) -> clientFileProgramLinkIds.contains program.get('id')
					        .map (program) -> program.get('name')

							console.log "program names: ", programNames.toJS()

							cb()

						# get event headers
						(cb) =>
							ActiveSession.persist.progEvents.list clientFileId, (err, results) ->
								if err
									cb err
									return

								progEventsHeaders = results
								cb()

						# read each event
						(cb) =>
							Async.map progEventsHeaders.toArray(), (progEvent, cb) ->
								ActiveSession.persist.progEvents.readLatestRevisions clientFileId, progEvent.get('id'), 1, cb
							, (err, results) ->
								if err
									cb err
									return

								progEvents = Imm.List(results).map (revision) -> revision.last()
								cb()

						# csv format: id, timestamp, username, title, description, start time, end time
						(cb) =>
							progEvents = progEvents
							.filter (progEvent) -> progEvent.get('status') isnt "cancelled"
							.map (progEvent) ->
								return {
									id: progEvent.get('id')
									timestamp: Moment(progEvent.get('timestamp'), TimestampFormat).format('YYYY-MM-DD HH:mm:ss')
									author: progEvent.get('author')
									clientName
									programs: "\"#{programNames.toJS().join(", ")}\""
									title: progEvent.get('title')
									description: progEvent.get('description')
									startDate: Moment(progEvent.get('startTimestamp'), TimestampFormat).format('YYYY-MM-DD HH:mm:ss')
									endDate: Moment(progEvent.get('endTimestamp'), TimestampFormat).format('YYYY-MM-DD HH:mm:ss')
								}

							cb()

					], (err) =>
						if err
							cb err
							return

						console.log "Done iterating over client", clientName
						cb(null, progEvents)

				, (err, results) =>
					if err
						if err instanceof CustomError
							handleCustomError err
							return

						CrashHandler.handle err
						return

					progEvents = Imm.List(results).flatten()

					# TODO: Move to series
					CSVConverter.json2csv progEvents.toJS(), (err, result) =>
						if err
							CrashHandler.handle err
							return

						csv = result
						@_updateProgress(100)


						# destination path must exist in order to save
						if path.length > 1
							Fs.writeFile path, csv, (err) =>
								@setState {isLoading: false}

								if err
									# TODO: Account for write errors without hard-crash
									CrashHandler.handle err
									return

								if isConfirmClosed isnt true
									Bootbox.alert {
										title: "Save Successful"
										message: "Events exported to: #{path}"
									}
									# isConfirmClosed = true


		_saveMetrics: (path) ->
			isConfirmClosed = false
			metrics = null
			@_updateProgress 0, "Saving #{Term 'Metrics'} to CSV..."

			# Map over client files
			Async.map @props.clientFileHeaders.toArray(), (clientFile, cb) =>

				metricsResult = Imm.List()

				metricDefinitionHeaders = null
				metricDefinitions = null
				progNoteHeaders = null
				progNotes = null
				clientFileId = clientFile.get('id')
				clientName = renderName clientFile.get('clientName')
				metricsList = null
				clientFileProgramLinkIds = null
				programHeaders = null
				programs = @props.programs
				programNames = null
				csv = null

				Async.series [
					# get clientfile program links
					(cb) =>
						@_updateProgress 5
						clientFileProgramLinkIds = @props.clientFileProgramLinks
						.filter (link) ->
							link.get('clientFileId') is clientFileId and
							link.get('status') is "enrolled"
						.map (link) ->
							link.get('programId')

						console.log "link IDs: ", clientFileProgramLinkIds.toJS()

						cb()

					(cb) =>
						programNames = programs
						.filter (program) -> clientFileProgramLinkIds.contains program.get('id')
				        .map (program) -> program.get('name')

						console.log "program names: ", programNames.toJS()

						cb()

					# List metric definition headers
					(cb) =>
						@_updateProgress 10
						ActiveSession.persist.metrics.list (err, results) ->
							if err
								cb err
								return

							metricDefinitionHeaders = results
							cb()

					# Retrieve all metric definitions
					(cb) =>
						@_updateProgress 20
						Async.map metricDefinitionHeaders.toArray(), (metricHeader, cb) ->
							ActiveSession.persist.metrics.readLatestRevisions metricHeader.get('id'), 1, cb
						, (err, results) ->
							if err
								cb err
								return

							metricDefinitions = Imm.List(results).map (revision) -> revision.last()
							cb()

					# List progNote headers
					(cb) =>
						@_updateProgress 30
						ActiveSession.persist.progNotes.list clientFileId, (err, results) ->
							if err
								cb err
								return

							progNoteHeaders = results
							cb()

					# Retrieve progNotes
					(cb) =>
						@_updateProgress 40
						Async.map progNoteHeaders.toArray(), (progNoteHeader, cb) ->
							ActiveSession.persist.progNotes.readLatestRevisions clientFileId, progNoteHeader.get('id'), 1, cb
						, (err, results) ->
							if err
								cb err
								return

							progNotes = Imm.List(results).map (revision) -> revision.last()
							cb()

					# Filter out full list of metrics
					(cb) =>
						@_updateProgress 50
						fullProgNotes = progNotes.filter (progNote) =>
							progNote.get('type') is "full" and
							progNote.get('status') isnt "cancelled"

						Async.map fullProgNotes.toArray(), (progNote, cb) =>

							progNoteMetrics = progNote.get('units').flatMap (unit) =>
								unitType = unit.get('type')

								switch unitType
									when 'basic'
										metrics = unit.get('metrics')
									when 'plan'
										metrics = unit.get('sections').flatMap (section) ->
											section.get('targets').flatMap (target) ->
												target.get('metrics')
									else
										cb new Error "Unknown unit type: #{unitType}"

								return metrics

							progNoteTimestamp = progNote.get('backdate') or progNote.get('timestamp')

							# Apply timestamp with custom format
							timestamp = Moment(progNoteTimestamp, TimestampFormat)
							.format('YYYY-MM-DD HH:mm:ss')

							# Model output format of metric object
							progNoteMetrics = progNoteMetrics.map (metric) ->
								return {
									timestamp
									authorUsername: progNote.get('author')
									clientFileId
									clientName
									metricId: metric.get('id')
									programs: "\"#{programNames.toJS().join(", ")}\""
									metricName: metric.get('name')
									metricDefinition: metric.get('definition')
									metricValue: metric.get('value')
								}

							console.info "progNoteMetrics", progNoteMetrics.toJS()
							cb null, progNoteMetrics

						, (err, results) ->
							if err
								cb err
								return

							metricsList = Imm.fromJS(results).flatten(true)
							cb()


				], (err) =>
					if err
						cb err
						return

					console.log "Done iterating over client: ", clientName
					cb(null, metricsList)

			, (err, results) =>
				if err
					if err instanceof Persist.CustomError
						handleCustomError err
						return

					CrashHandler.handle err
					return


				metricsList = Imm.List(results).flatten()

				console.log "Final Metrics result: ", metricsList.toJS()


				CSVConverter.json2csv metricsList.toJS(), (err, result) =>
					if err
						cb err
						return

					csv = result
					@_updateProgress 100


					# Destination path must exist in order to save
					if path.length > 1
						Fs.writeFile path, csv, (err) =>
							if err
								CrashHandler.handle err
								return

							console.info "Destination Path:", path
							@setState {isLoading: false}

							if isConfirmClosed isnt true
								Bootbox.alert {
									title: "Save Successful"
									message: "Metrics exported to: #{path}"
								}
								isConfirmClosed = true


		_saveBackup: (savepath) ->

			totalFiles = 0

			@setState {
				isLoading: true
				exportProgress: {message: "Preparing to archive... "}
			}

			walkSync = (dir) =>
				files = Fs.readdirSync(dir)
				files.forEach (file) ->
					if Fs.statSync(Path.join(dir, file)).isDirectory()
						totalFiles++
						walkSync(Path.join(dir, file))
					else
						totalFiles++
					return

			Async.series [

				(cb) =>
					unless savepath.length > 1
						err = new Error('nopath')
						cb err
						return

					walkSync(Config.backend.dataDirectory)
					cb()

				(cb) =>
					unless totalFiles > 0
						err = new Error('nofiles')
						cb err
						return
					cb()

				(cb) =>
					output = Fs.createWriteStream(savepath)
					archive = Archiver('zip', {store:true})
					.on 'error', (err) =>
						cb err
						return
					.on 'finish', (err) =>
						clearInterval(progressCheck)
						@setState {isLoading: false}
						Bootbox.alert {
							title: "Backup Complete (#{@_prettySize output.bytesWritten})!"
							message: "Saved to: #{savepath}"
						}
						cb()

					archive.directory(Config.backend.dataDirectory, '')
					archive.finalize()
					archive.pipe(output)

					progressCheck = setInterval =>
						@setState {
							exportProgress: {message: "Writing #{@_prettySize(archive.pointer())} to #{Path.basename(savepath)}..." }
						}
					, 200

			], (err) =>
				if err
					@setState {isLoading: false}

					Bootbox.alert {
						title: "Data Backup Failed"
						message: """
							Unable to create archive. Please check your network connection and try again.
							If the problem persists, contact #{Config.productName} support with the following error:
							\"#{err}\".
						"""
					}
					console.error err
					return

	return ExportManagerTab

module.exports = {load}
