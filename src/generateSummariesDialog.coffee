# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# PROTOTYPE FEATURE

Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'

Config = require './config'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)
	Dialog = require('./dialog').load(win)

	{TimestampFormat, stripMetadata} = require('./persist/utils')
	{FaIcon, renderName} = require('./utils').load(win)


	SummaryManagerTab = React.createFactory React.createClass
		displayName: 'SummaryManagerTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {
			isBuilding: true
			progressMessage: "Generating summaries..."
			progressPercent: 0

			summariesString: null
		}

		componentWillMount: ->
			@_buildSummariesData()

		render: ->
			return Dialog({
				title: "Shift Summary Log"
				onClose: @props.onClose
			},
				R.div({className: 'summaryManagerTab'},
					R.div({className: 'main'},
						(if @state.isBuilding
							Spinner {
								isVisible: true
								isOverlay: false
								message: @state.progressMessage
								percent: @state.progressPercent
							}
						else
							R.textarea({
								value: @state.summariesString
							})
						)
					)
				)
			)

		_buildSummariesData: ->
			userProgramId = ActiveSession.programId
			userHasProgramId = !!userProgramId

			clientFileIds = null
			summaryObjects = null

			# 1. Determine which clientFileIds we need to search for summaries in
			# 2. Find progNotes from today that include a summary, choose most recent one

			Async.series [
				(cb) =>
					# Use all clientFileIds if user isn't in a program
					if not userHasProgramId
						console.log "No userProgram, so using all clientFiles..."
						ActiveSession.persist.clientFiles.list (err, result) =>
							if err
								cb err
								return

							clientFileIds = result.map (clientFile) -> clientFile.get('id')
							cb()

						return

					# User's in a program, so let's figure out which clientFileIds to fetch summaries from
					console.log "Has userProgram, so let's look at the clientFileProgramLinks..."
					ActiveSession.persist.clientFileProgramLinks.list (err, result) =>
						if err
							cb err
							return

						# Discard programLinks that don't match user's program, and inactive ones
						clientFileProgramLinkHeaders = result.filter (link) ->
							link.get(programId) is userProgramId and
							link.get('status') is 'default'

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
						progNotesWithSummary = null

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

											console.log "progNoteHeadersFromToday", progNoteHeadersFromToday.toJS()
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
											progNotesWithSummary = Imm.List(results).flatten(true)
											console.log "progNotesWithSummary", progNotesWithSummary.toJS()
											cb()

								], cb

						], (err) =>
							if err
								cb err
								return

							# We're only interested in the most recent progNoteWithSummary
							progNote = progNotesWithSummary.last()

							result = Imm.fromJS {
								clientFile
								progNote
							}

							# Update the progressPercent
							progressPercent = @state.progressPercent + clientFilePercentValue
							@setState {progressPercent}

							console.log "Processed clientFile"
							# Ok, next clientFile please!
							cb null, result

					, (err, results) =>
						if err
							cb err
							return

						console.log "Building summaryObjects..."

						summaryObjects = Imm.List(results)
						console.info "summaryObjects:", summaryObjects.toJS()
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

				console.log "Done generating data..."

				# Finally,
				# 1. Filter out clientFiles without summaries
				# 2. Format each one to a string template
				# 3. Concatenate everything into 1 giant string
				summariesString = summaryObjects
				.filter (obj) -> obj.get('progNote')
				.map (obj) ->
					date = obj.getIn(['progNote', 'backdate']) or obj.getIn(['progNote', 'timestamp'])
					clientName = renderName(obj.getIn ['clientFile', 'clientName'])
					recordId = obj.getIn ['clientFile', 'recordId']
					summary = obj.getIn ['progNote', 'summary']

					return """
						#{clientName} - #{Config.clientFileRecordId.label} #{recordId}\n
						SUMMARY: #{summary}
					"""
				.toJS()
				.join "\n\n"

				console.log "summariesString", summariesString

				# All done!
				@setState {
					summariesString
					isBuilding: false
				}


	return SummaryManagerTab


module.exports = {load}