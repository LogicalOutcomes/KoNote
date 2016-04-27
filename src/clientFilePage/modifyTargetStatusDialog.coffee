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
	Spinner = require('../spinner').load(win)

	ModifyTargetStatusDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@refs.reasonField.focus()

		getInitialState: ->
			return {
				reason: ''
			}

		render: ->
			Dialog({
				ref: 'dialog'
				title: "Change #{Term 'Target'} Status"
				onClose: @props.onClose
			},
				R.div({className: 'cancelProgNoteDialog'},
					R.div({className: 'alert alert-warning'},
						"This will change the status of the #{Term 'target'}"
					)
					R.div({className: 'form-group'},
						R.label({}, "Reason for status change:"),
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
						}, "Confirm")
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
			# @refs.dialog.setIsLoading true
			newTarget = @props.target
			.set('status', @props.newStatus)
			.set('statusReason', @state.reason)

			ActiveSession.persist.planTargets.createRevision newTarget, (err, updatedTarget) =>
				if err
					console.log err
					return
				console.log "updated target: ", updatedTarget.toJS()
				
				# @props.onTargetUpdate newTarget

				
		

				# Persist will trigger an event to update the UI
				

	return ModifyTargetStatusDialog

module.exports = {load}
