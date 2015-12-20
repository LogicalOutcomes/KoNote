# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'

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
	Spinner = require('../spinner').load(win)

	CancelProgNoteDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@refs.reasonField.focus()

		getInitialState: ->
			return {
				reason: ''
			}

		render: ->
			Dialog({
				title: "Rename #{Term 'Client File'}"
				onClose: @props.onClose
			},
				R.div({className: 'cancelProgNoteDialog'},
					R.div({className: 'form-group'},
						R.label({}, "Reason for cancelling this entry:"),
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
						}, "Cancel entry")
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

		_submit: ->
			@setState {isLoading: true}

			updatedProgNote = @props.progNote
			.set('status', 'cancelled')
			.set('statusReason', @state.reason)

			ActiveSession.persist.progNotes.createRevision updatedProgNote, (err) ->
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				# Persist will trigger an event to update the UI

	return CancelProgNoteDialog

module.exports = {load}
