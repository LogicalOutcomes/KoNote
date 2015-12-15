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
		
		componentDidMount: ->
			# Register listeners for full data backup
			timestamp = Moment().format('YYYY-MM-DD')
			fileName = "konote-backup-#{timestamp}.zip"

			$chooser = $(@refs.inputDialog.getDOMNode())
			.attr("nwsaveas", fileName)
			.on('change', (event) => @_saveDataDirectory event.target.value)
		
		render: ->
			return R.div({className: 'exportManagerTab'},
				R.div({className: 'header'},
					R.h1({}, "Export Data")
				)
				R.div({className: 'main'},
					R.button({
						className: 'btn btn-primary btn-lg'
						onClick: @_exportMetrics
					}, "Export Metrics")
				)
				R.input({
					className: 'hidden'
					type: 'file'
					ref: 'inputDialog'
				})
				R.div({className: 'main'},
					R.button({
						className: 'btn btn-primary btn-lg'
						onClick: @_exportDataDirectory
					}, "Backup Data")
				)
			)

		_exportMetrics: ->
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
							ActiveSession.persist.progNotes.read clientFileId, progNoteHeader.get('id'), cb
						, (err, results) ->
							if err
								cb err
								return

							progNotes = Imm.List results
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
						
				], cb
			, (err) ->
				if err
					CrashHandler.handle err
					return

				console.info "CSV Data:", csv
				console.info "Done!"
				
		_exportDataDirectory: ->
			chooser = React.findDOMNode(@refs.inputDialog)
			chooser.click()
			
		_saveDataDirectory: (path) ->
			if path.length > 1
				output = Fs.createWriteStream(path);
				archive = Archiver('zip');

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