# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
Imm = require 'immutable'
Persist = require './persist'
Moment = require 'moment'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	Spinner = require('./spinner').load(win)
	{FaIcon} = require('./utils').load(win)
	{TimestampFormat, stripMetadata} = require('./persist/utils')


	SummaryManagerTab = React.createFactory React.createClass
		displayName: 'SummaryManagerTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {
			isBuilding: false
			buildProgress: {
				message: null
				percent: null
			}
		}

		render: ->
			return R.div({className: 'summaryManagerTab'},
				R.div({className: 'header'},
					R.h1({}, "Shift Summary Log")
				)
				R.div({className: 'main'},
					Spinner {
						isVisible: @state.isLoading
						isOverlay: true
						# message: @state.exportProgress.message
						# percent: @state.exportProgress.percent
					}
					R.div({},
						R.p({},
							"This will build a log of all shift summaries recorded today"
						)
						R.button({
							className: 'btn btn-default btn-lg'
							onClick: @_buildLog
						}, "Build Log")
					)
				)
			)

		_buildLog: ->
			console.log "Build!"

			userProgramId = ActiveSession.programId
			userHasProgramId = !!userProgramId

			clientFileIds = null

			Async.series [
				(cb) =>
					# Use all clientFileIds if user isn't in a program
					if not userHasProgramId
						ActiveSession.persist.clientFiles.list (err, result) =>
							if err
								cb err
								return

							clientFileIds = result.map (clientFile) -> clientFile.get('id')
							cb()
							return

					# User's in a program, so let's figure out which clientFiles to fetch summaries from
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
					# Fetch each clientFile, and get today's latest summary if exists
					Async.map clientFileIds.toArray(), (clientFileId, cb) ->

						clientFile = null
						progNoteHeaders = null
						progNote = null

						Async.series [
							(cb) =>
								ActiveSession.persist.clientFiles.readLatestRevisions clientFileId, 1, (err, revisions) =>
									if err
										cb err
										return

									clientFile = stripMetadata revisions.get(0)
									cb()

							(cb) =>
								ActiveSession.persist.progNotes.list clientFileId, (err, results) ->
									if err
										cb err
										return

									# Timestamp must be from today, and summary must exist
									progNoteHeaders = results
									.filter (progNote) ->
										timestamp = Moment(progNote.get('timestamp'), Persist.TimestampFormat)
										isSameDay = timestamp.isSame(Moment(), 'day',)
										return isSameDay and progNote.has('summary')
									.sortBy (progNote) ->
										progNote.get('timestamp')

									cb()

							(cb) =>
								# Skip if no progNotes to load
								if progNoteHeaders.isEmpty()
									cb()
									return

								# We only want the latest progNote/summary
								progNoteId = progNoteHeaders.last().get('id')

								ActiveSession.persist.progNote.readLatestRevisions clientFileId, progNoteId, (err, revisions) =>
									if err
										cb err
										return

									progNote = stripMetadata revisions.get(0)
									cb()

						], (err) ->
							if err
								cb err
								return

							summaryObject = Imm.fromJS {
								clientFile
								progNoteWithSummary: progNote
							}

							cb null, summaryObject

					, (err, results) ->
						if err
							cb err
							return

						summaryObjects = Imm.List(results)

						console.info "ProgNotes by clientFile:", summaryObjects.toJS()
						cb()


			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				# Success!
				console.info "Success!"


	return SummaryManagerTab


module.exports = {load}