# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
_ = require 'underscore'
Imm = require 'immutable'
Persist = require './persist'
Fs = require 'fs'
Archiver = require 'archiver'
CSVConverter = require 'json-2-csv'
GetSize = require 'get-folder-size'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Moment = require 'moment'

	Config = require('./config')
	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)	
	{FaIcon, renderName, showWhen} = require('./utils').load(win)
	{TimestampFormat} = require('./persist/utils')

	ExportManagerTab = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		
		getInitialState: ->
			return {
				progress: 0
				message: null
				inProgress: null
			}
		
		render: ->
			return R.div({className: 'exportManagerTab'},
				R.div({className: 'header'},
					R.h1({}, "Export Data")
				)
				R.div({className: 'main'},
					R.div({
						className: [
							'progressSpinner'
							showWhen @state.inProgress
						].join ' '
					},
						Spinner {
							isVisible: true
							isProgressOnly: true
							message: @state.message
							percent: @state.progress
						}
					)
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
					}, "Export Metrics to CSV")
					R.button({
						className: 'btn btn-default btn-lg'
						onClick: @_export.bind null, {
							defaultName: "konote-events"
							extension: 'csv'
							runExport: @_saveEvents
						}
					}, "Export Events to CSV")
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
			# Map over client files
			Async.map @props.clientFileHeaders.toArray(), (clientFile, cb) =>
				progEventsHeaders = null
				progEvents = null
				progEventsList = null
				clientFileId = clientFile.get('id')
				clientName = renderName clientFile.get('clientName')
				csv = null

				Async.series [
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
								title: progEvent.get('title')
								description: progEvent.get('description')
								startDate: Moment(progEvent.get('startTimestamp'), TimestampFormat).format('YYYY-MM-DD HH:mm:ss')
								endDate: Moment(progEvent.get('endTimestamp'), TimestampFormat).format('YYYY-MM-DD HH:mm:ss')
							}
						cb null, progEvents
						, (err, results) ->
							if err
								cb err
								return
							progEvents = Imm.List results
							cb()
					
					# convert to csv
					(cb) =>
						CSVConverter.json2csv progEvents.toJS(), (err, result) ->
							csv = result
							cb()
					
				], (err) ->
					if err
						CrashHandler.handle err
						return

					# destination path must exist in order to save
					if path.length > 1
						Fs.writeFile path, csv, (err) ->
							if err
								CrashHandler.handle err
								return

							Bootbox.alert {
								title: "Save Successful"
								message: "Events exported to: #{path}"
							}
	
		_saveMetrics: (path) ->
			metrics = null

			# Map over client files
			Async.map @props.clientFileHeaders.toArray(), (clientFile, cb) =>

				metricsResult = Imm.List()

				metricDefinitionHeaders = null
				metricDefinitions = null
				progNoteHeaders = null
				progNotes = null				
				clientFileId = clientFile.get('id')
				metricsList = null
				csv = null

				Async.series [
					# List metric definition headers
					(cb) =>
						ActiveSession.persist.metrics.list (err, results) ->
							if err
								cb err
								return

							metricDefinitionHeaders = results
							cb()

					# Retrieve all metric definitions
					(cb) =>
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
						ActiveSession.persist.progNotes.list clientFileId, (err, results) ->
							if err
								cb err
								return

							progNoteHeaders = results
							cb()

					# Retrieve progNotes
					(cb) =>
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

							# Get clientFile's full name
							clientFileId = progNote.get('clientFileId')
							clientFileName = renderName(
								@props.clientFileHeaders
								.find (clientFile) -> clientFile.get('id') is clientFileId
								.get('clientName')
							)

							# Model output format of metric object
							progNoteMetrics = progNoteMetrics.map (metric) ->
								return {
									timestamp
									authorUsername: progNote.get('author')
									clientFileId
									clientFileName									
									metricId: metric.get('id')
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
					
					# Convert to CSV
					(cb) =>
						CSVConverter.json2csv metricsList.toJS(), (err, result) ->
							csv = result
							cb()
						
				], (err) ->
					if err
						CrashHandler.handle err
						return

					console.info "CSV Metric Data:", csv

					# Destination path must exist in order to save
					if path.length > 1
						Fs.writeFile path, csv, (err) ->
							if err
								CrashHandler.handle err
								return

							console.info "Destination Path:", path

							Bootbox.alert {
								title: "Save Successful"
								message: "Metrics exported to: #{path}"
							}
			
		_prettySize: (bytes) ->
			if bytes / 1024 > 1024
				return (bytes/1024/1024).toFixed(2) + "MB"
			return (bytes/1024).toFixed(2) + "KB"
		
		_saveBackup: (path) ->
			@setState {
				progress: 1
				inProgress: true
			}
			totalSize = 0
			
			# Destination path must exist in order to save
			if path.length > 1
				
				GetSize 'data', (err, size) ->
					if err
						Bootbox.dialog {
							title: "Error Calculating Filesize"
							message: """
								The backup may be incomplete!
								<br><br>
								<span class='error'>#{err}</span>
							"""
							buttons: {
								cancel: {
									label: "Cancel"
									className: 'btn-default'
									callback: =>
										return
								}
								proceed: {
									label: "Continue"
									className: 'btn-primary'
								}
							}
						}
						console.error err
					totalSize = size or 0

				output = Fs.createWriteStream(path)
				archive = Archiver('zip')

				output.on 'finish', (->
					clearInterval(progress)
					@setState {progress: 100}
					backupSize = @_prettySize output.bytesWritten
					Bootbox.alert {
						title: "Backup Complete (#{backupSize})"
						message: "Saved to: #{path}"
						callback: =>
							@setState {inProgress: false}
					}
				).bind(this)
				.on 'error', ((err) ->
					clearInterval(progress)
					Bootbox.alert {
						title: "Error Saving File"
						message: """
							<span class='error'>#{err}</span>
							<br>
							Please try again.
						"""
						callback: =>
							@setState {
								inProgress: false
								progress: 0
							}
					}
					console.error err
				).bind(this)

				archive.on 'error', (err) ->
					Bootbox.alert {
						title: "Error Saving File"
						message: """
							<span class='error'>#{err}</span>
							<br>
							Please try again.
						"""
						callback: =>
							output.close()
							@setState {
								inProgress: false
								progress: 0
							}
					}

				archive.bulk [{
					expand: true
					cwd: Config.dataDirectory
					src: ['**/*']
					dest: 'data'
				}]

				archive.finalize()

				archive.pipe(output)
				progress = setInterval (->
					written = archive.pointer()
					currentProgress = Math.floor((written/totalSize) * 100)
					messageText = "(" + @_prettySize(written) + " / " + @_prettySize(totalSize) + ")"
					@setState {
						progress: currentProgress
						message: messageText
					}
				).bind(this), 100
			
	return ExportManagerTab

module.exports = {load}
