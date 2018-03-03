# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Prototyped Griffin feature that generates a string/list of today's shift summaries

Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'

Config = require './config'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	ReactDOMServer = win.ReactDOMServer

	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)
	Dialog = require('./dialog').load(win)

	{TimestampFormat, stripMetadata} = require('./persist/utils')
	{FaIcon, renderName} = require('./utils').load(win)
	Term = require('./term')


	GenerateSummariesDialog = React.createFactory React.createClass
		displayName: 'GenerateSummariesDialog'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		getInitialState: -> {
			showDialog: false
			isBuilding: true
			progressMessage: "Generating summaries..."
			progressPercent: 0

			summariesString: null
		}

		componentWillMount: ->
			@_buildSummariesData()

		render: ->
			unless @state.showDialog
				return null

			return Dialog({
				title: "Today's Shift Summary Log"
				onClose: @props.onClose
			},
				R.div({className: 'generateSummariesDialog'},
					(if @state.isBuilding
						Spinner {
							isVisible: true
							isOverlay: false
							message: @state.progressMessage
							percent: @state.progressPercent
						}
					else
						R.div({
							id: 'summariesContainer'
							className: 'animated fadeIn'
						},
							R.textarea({
								ref: 'textarea'
								className: 'form-control'
								value: @state.summariesString
								onChange: (event) -> event.preventDefault()
							})
							R.br({})
							R.button({
								className: 'btn btn-lg btn-primary'
								onClick: @_copyToClipboard
							},
								"Copy"
								' '
								FaIcon('copy')
							)
						)
					)
				)
			)

		_copyToClipboard: ->
			@refs.textarea.select()

			clipboard = nw.Clipboard.get()
			clipboard.set @state.summariesString

			notification = new Notification "Shift Summaries", {
				body: "Copied to clipboard"
				icon: Config.iconNotification
			}

			setTimeout(->
				notification.close()
			, 3000)

		_buildSummariesData: ->
			userProgramId = global.ActiveSession.programId

			clientFileIds = null
			summaryObjects = null
			programs = null

			# 1. Determine which clientFileIds we need to search for summaries in
			# 2. Find progNotes from today that include a summary, choose most recent one

			Async.series [
				(cb) =>
					ActiveSession.persist.programs.list (err, result) =>
						if err
							cb err
							return
						programs = result
						cb()

				(cb) =>
					# If user not in a program, prompt to choose one
					if userProgramId or programs.size is 0
						cb()
					else
						# Build programDropdown markup
						programDropdown = R.select({
							id: 'programDropdown'
							className: 'form-control '
						},
							R.option({value: ''}, "All #{Term 'programs'}")
							console.log programs
							(programs.map (program) ->
								R.option({
									key: program.get('id')
									value: program.get('id')
								},
									program.get('name')
								)
							)
						)

						Bootbox.dialog {
							title: "Select #{Term 'program'}"
							message: R.div({},
								"Your user is not currently assigned to any #{Term 'program'}.",
								R.br(), R.br(),
								"Please select which #{Term 'program'} you ",
								"would like to generate summaries for, or ",
								"generate summaries for all #{Term 'programs'}.",
								R.br(), R.br(),
								programDropdown
							)
							closeButton: false
							buttons: {
								cancel: {
									label: "Cancel"
									className: "btn-default"
									callback: =>
										Bootbox.hideAll()
										@props.onClose()
								}
								success: {
									label: "Show Summaries"
									className: "btn-success"
									callback: =>
										userProgramId = $('#programDropdown').val()
										cb()
								}
							}
						}

				(cb) =>
					@setState {showDialog: true}
					# Use all clientFileIds if user isn't in a program
					if not userProgramId
						ActiveSession.persist.clientFiles.list (err, result) =>
							if err
								cb err
								return

							clientFileIds = result.map (clientFile) -> clientFile.get('id')
							cb()

						return

					# User's in a program, so let's figure out which clientFileIds to fetch summaries from
					ActiveSession.persist.clientFileProgramLinks.list (err, result) =>
						if err
							cb err
							return

						# Discard programLinks that don't match user's program, and inactive ones
						clientFileProgramLinkHeaders = result.filter (link) ->
							link.get('programId') is userProgramId and
							link.get('status') is 'enrolled'

						# Generate list of clientFileIds to fetch
						clientFileIds = clientFileProgramLinkHeaders.map (link) ->
							link.get('clientFileId')

						cb()

				(cb) =>
					@setState {progressPercent: 10}
					clientFilePercentValue = 90 / clientFileIds.size

					# Extract summary from each clientFile
					Async.map clientFileIds.toArray(), (clientFileId, cb) =>

						clientFile = null
						progNoteHeadersFromToday = null
						progNotesFromToday = null

						Async.parallel [
							(cb) =>
								# Read the clientFile data
								ActiveSession.persist.clientFiles.readLatestRevisions clientFileId, 1, (err, revisions) =>
									if err
										cb err
										return

									clientFile = stripMetadata revisions.get(0)
									cb()

							(cb) =>
								# Find all progNotes containing a summary, from today
								Async.series [
									(cb) =>
										ActiveSession.persist.progNotes.list clientFileId, (err, results) ->
											if err
												cb err
												return

											# Timestamp must be from today, and summary must exist
											progNoteHeadersFromToday = results
											.filter (progNote) ->
												timestamp = Moment(progNote.get('timestamp'), TimestampFormat)
												return timestamp.isSame(Moment(), 'day',)
											.sortBy (progNote) ->
												progNote.get('backdate') or progNote.get('timestamp')

											cb()

									(cb) =>
										Async.map progNoteHeadersFromToday.toArray(), (progNoteHeader, cb) ->
											progNoteId = progNoteHeader.get('id')
											ActiveSession.persist.progNotes.readLatestRevisions clientFileId, progNoteId, 1, cb
										, (err, results) ->
											if err
												cb err
												return

											# Flatten from [[obj], [obj]] -> [obj, obj]
											progNotesFromToday = Imm.List(results).flatten(true)
											cb()

								], cb

						], (err) =>
							if err
								cb err
								return

							# We're only interested in the most recent progNoteWithSummary
							progNote = progNotesFromToday.last()

							result = Imm.fromJS {
								clientFile
								progNote
							}

							# Update the progressPercent
							progressPercent = @state.progressPercent + clientFilePercentValue
							@setState {progressPercent}

							# Ok, next clientFile please!
							cb null, result

					, (err, results) =>
						if err
							cb err
							return

						summaryObjects = Imm.List(results)
						cb()

			], (err) =>
				if err
					@setState {isBuilding: false}

					if err instanceof Persist.IOError
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				# Finally,
				# 1. Filter out clientFiles without summaries
				# 2. Format each one to a string template
				# 3. Concatenate everything into 1 giant string
				# TODO: Refactor all this

				todaysDate = Moment().format('MMMM Do, YYYY')
				titleString = """
					Shift Summaries - #{todaysDate}
					------------------------------------------------\n\n
				"""

				summariesString = summaryObjects
				.filter (obj) -> obj.get('progNote') and obj.getIn(['progNote', 'summary'])
				.map (obj) ->
					date = obj.getIn(['progNote', 'backdate']) or obj.getIn(['progNote', 'timestamp'])
					time = Moment(date, TimestampFormat).format('h:mma')
					clientName = renderName(obj.getIn ['clientFile', 'clientName'])
					recordId = obj.getIn ['clientFile', 'recordId']
					author = obj.getIn ['progNote', 'author']
					summary = obj.getIn ['progNote', 'summary']

					recordIdString = if recordId then " (#{Config.clientFileRecordId.label} #{recordId})" else ''

					return """
						- #{clientName}#{recordIdString} - by #{author} @ #{time}
						#{summary}
					"""
				.toJS()
				.join "\n\n"

				if not summariesString
					summariesString = "(no summaries recorded today)"

				summariesString = titleString + summariesString

				# TODO: Refactor this
				missingSummariesString = summaryObjects
				.filter (obj) -> not obj.get('progNote') or not obj.getIn(['progNote', 'summary'])
				.map (obj) ->
					clientName = renderName(obj.getIn ['clientFile', 'clientName'])
					recordId = obj.getIn ['clientFile', 'recordId']

					recordIdString = if recordId then " (#{Config.clientFileRecordId.label} #{recordId})" else ''

					return """
						- #{clientName}#{recordIdString}
					"""
				.toJS()
				.join "\n"


				if missingSummariesString.length > 0
					summariesString = [summariesString, missingSummariesString].join """
						\n\n
						No summaries recorded today for:
						------------------------------------------------\n
					"""

				# All done!
				@setState {
					summariesString
					isBuilding: false
				}


	return GenerateSummariesDialog


module.exports = {load}
