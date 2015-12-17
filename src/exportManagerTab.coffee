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

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	Moment = require 'moment'

	Config = require('./config')
	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)	
	{FaIcon, renderName} = require('./utils').load(win)
	{TimestampFormat} = require('./persist/utils')

	ExportManagerTab = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]	
		
		render: ->
			return R.div({className: 'exportManagerTab'},
				R.div({className: 'header'},
					R.h1({}, "Export Data")
				)
				R.div({className: 'main'},
					# Hidden input for handling file saving
					R.input({
						ref: 'nwsaveas'
						className: 'hidden'
						type: 'file'
					})

					R.button({
						className: 'btn btn-primary btn-lg'
						onClick: @_export.bind null, {
							defaultName: "konote-metrics"
							extension: 'csv'
							runExport: @_saveMetrics
						}
					}, "Export Metrics")
					R.button({
						className: 'btn btn-primary btn-lg'
						onClick: @_export.bind null, {
							defaultName: "konote-events"
							extension: 'csv'
							runExport: @_saveEvents
						}
					}, "Export Events")
					R.button({
						className: 'btn btn-primary btn-lg'
						onClick: @_export.bind null, {
							defaultName: "konote-backup"
							extension: 'zip'
							runExport: @_saveBackup
						}
					}, "Backup Data")
				)
			)

		_export: ({defaultName, extension, runExport}) ->
			timestamp = Moment().format('YYYY-MM-DD')
			# Configures hidden file inputs with custom attributes, and clicks it
			$nwsaveasInput = $(@refs.nwsaveas.getDOMNode())

			$nwsaveasInput
			.off()
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
							ActiveSession.persist.progEvents.read clientFileId, progEvent.get('id'), cb
						, (err, results) ->
							if err
								cb err
								return

							progEvents = Imm.List results
							cb()
							
					# csv format: id, timestamp, username, title, description, start time, end time
					(cb) =>
						progEvents = progEvents.map (event) ->
							return {
								id: event.get('id')
								timestamp: Moment(event.get('timestamp'), TimestampFormat).format('YYYY-MM-DD HH:mm:ss')
								author: event.get('author')
								clientName
								title: event.get('title')
								description: event.get('description')
								startDate: Moment(event.get('startTimestamp'), TimestampFormat).format('YYYY-MM-DD HH:mm:ss')
								endDate: Moment(event.get('endTimestamp'), TimestampFormat).format('YYYY-MM-DD HH:mm:ss')
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
							ActiveSession.persist.metrics.read metricHeader.get('id'), cb
						, (err, results) ->
							if err
								cb err
								return

							metricDefinitions = Imm.List results
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
							ActiveSession.persist.progNotes.readRevisions clientFileId, progNoteHeader.get('id'), cb
						, (err, results) ->
							if err
								cb err
								return

							progNotes = Imm.List(results)
							.map (progNoteHist) ->
								# Throw away history, just grab latest revision
								# TODO keep history for use in export?
								return progNoteHist.last()
							console.info "progNotes", progNotes.toJS()
							cb()

					# Filter out full list of metrics
					(cb) =>
						fullProgNotes = progNotes.filter (progNote) =>
							progNote.get('type') is 'full'

						console.info "fullProgNotes", fullProgNotes

						Async.map fullProgNotes.toArray(), (progNote, cb) =>
							console.info "progNote", progNote.toJS()							
							
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

							# Get backdate or timestamp from parent progNote
							progNoteTimestamp = if progNote.get('backdate')
								progNote.get('backdate')
							else
								# TODO should this use original creation
								# timestamp instead of last modified at?
								progNote.get('timestamp')

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

							console.info "metricsList", metricsList.toJS()
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
			
		_saveBackup: (path) ->
			console.log "Running save backup!"

			# Destination path must exist in order to save
			if path.length > 1
				output = Fs.createWriteStream(path)
				archive = Archiver('zip')

				output.on 'close', ->
					backupSize = (archive.pointer()/1000).toFixed(2)
					if backupSize > 1
						Bootbox.alert {
							title: "Backup Successful (#{backupSize}KB)"
							message: "Saved to: #{path}"
						}
					else
						Bootbox.alert {
							title: "Error"
							message: "Saved file size less than expected (#{backupSize}KB)."
						}
				.on 'error', (err) ->
					CrashHandler.handle err

				archive.on 'error', (err) ->
					CrashHandler.handle err

				archive.pipe(output)
				archive.bulk [{
					expand: true
					cwd: Config.dataDirectory
					src: ['**/*']
					dest: 'data'
				}]
			
				archive.finalize()

	return ExportManagerTab

module.exports = {load}
