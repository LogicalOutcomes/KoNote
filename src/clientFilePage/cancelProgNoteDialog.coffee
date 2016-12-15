# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'
Async = require 'async'

Config = require '../config'
Persist = require '../persist'
Term = require '../term'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('../crashHandler').load(win)
	Dialog = require('../dialog').load(win)
	{formatTimestamp} = require('../utils').load(win)


	CancelProgNoteDialog = React.createFactory React.createClass
		displayName: 'CancelProgNoteDialog'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@refs.reasonField.focus()

		getInitialState: ->
			return {
				reason: ''
			}

		getDefaultProps: ->
			return {
				progEvents: Imm.List()
				globalEvents: Imm.List()
			}

		render: ->
			Dialog({
				ref: 'dialog'
				title: "Discard #{Term 'Progress Note'}"
				onClose: @props.onClose
			},
				R.div({className: 'cancelProgNoteDialog'},
					R.div({className: 'alert alert-warning'},
						"This will discard the #{Term 'progress note'} entry,
						including any recorded #{Term 'metrics'}/#{Term 'events'}."
					)
					R.div({className: 'form-group'},
						R.label({}, "Reason for discarding this entry:"),
						R.textarea({
							className: 'form-control'
							style: {minWidth: 350, minHeight: 100}
							ref: 'reasonField'
							onChange: @_updateReason
							value: @state.reason
							onKeyDown: @_onEnterKeyDown
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel
						}, "Cancel")
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
							disabled: not @state.reason
						}, "Discard entry")
					)
				)
			)

		_cancel: ->
			@props.onCancel()

		_updateReason: (event) ->
			@setState {reason: event.target.value}

		_onEnterKeyDown: (event) ->
			if event.which is 13 and @state.firstName and @state.lastName
				@_submit()

		_cancelEvents: (events) ->
			return events
			.filter (progEvent) -> progEvent.get('status') is 'default'
			.map (progEvent) =>
				progEvent
				.set('status', 'cancelled')
				.set('statusReason', @state.reason)

		_submit: ->
			# Cancel progNote with reason
			cancelledProgNote = @props.progNote
			.set('status', 'cancelled')
			.set('statusReason', @state.reason)

			# Cancel only active/default events, with same reason
			cancelledProgEvents = @_cancelEvents @props.progEvents
			cancelledGlobalEvents = @_cancelEvents @props.globalEvents

			cancelledEvents = cancelledProgEvents
			.concat(cancelledGlobalEvents)
			.sortBy (event) -> event.get('startTimestamp')

			# Build HTML for each event entry
			eventsList = cancelledEvents.toJS().map ({title, startTimestamp, endTimestamp, relatedProgEventId}) ->
				# relatedProgEventId indicates this is a globalEvent
				if relatedProgEventId?
					title += " (#{Term 'global event'})"

				return """
					<li>
						<strong>#{title}</strong>\n
						<div>From: <em>#{formatTimestamp startTimestamp}</em></div>
						<div>Until: <em>#{formatTimestamp endTimestamp}</em></div>
					</li>
				"""
			.join('')

			# Build HTML for events warning
			eventsMessage = """
				<br><br>
				The following #{Term 'events'} will also be cancelled:
				<ul>
					#{eventsList}
				</ul>
			"""

			eventsMessage = if cancelledEvents.isEmpty() then '' else eventsMessage

			# Prompt the user, include eventsMessage if any to show
			Bootbox.confirm """
				Are you sure you want to cancel this #{Term 'progress note'}?
				#{eventsMessage}
			""", (ok) =>
				if ok
					@_cancelProgNote cancelledProgNote, cancelledProgEvents, cancelledGlobalEvents


		_cancelProgNote: (progNote, progEvents, globalEvents) ->
			Async.series [
				(cb) =>
					ActiveSession.persist.progNotes.createRevision progNote, cb

				(cb) =>
					Async.map progEvents.toArray(), (progEvent, cb) ->
						ActiveSession.persist.progEvents.createRevision progEvent, cb
					, cb

				(cb) =>
					Async.map globalEvents.toArray(), (globalEvent, cb) ->
						ActiveSession.persist.globalEvents.createRevision globalEvent, cb
					, cb

			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				# Persist will trigger an event to update the UI
				@props.onSuccess()


	return CancelProgNoteDialog

module.exports = {load}
