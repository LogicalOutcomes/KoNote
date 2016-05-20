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

	ModifySectionStatusDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@refs.statusReasonField.focus()

		getInitialState: ->
			return {statusReason: ''}

		render: ->
			Dialog({
				ref: 'dialog'
				title: @props.title
				onClose: @props.onClose
			},
				R.div({className: 'modifyTargetStatusDialog'},
					R.div({className: 'alert alert-warning'}, @props.message)
					R.div({className: 'form-group'},
						R.label({}, @props.reasonLabel),
						R.textarea({
							className: 'form-control'
							style: {minWidth: 350, minHeight: 100}
							ref: 'statusReasonField'
							onChange: @_updateStatusReason
							value: @state.statusReason
							placeholder: "Please specify a reason..."
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						}, "Cancel")
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
							disabled: not @state.statusReason
						}, "Confirm")
					)
				)
			)

		_updateStatusReason: (event) ->
			@setState {statusReason: event.target.value}

		_submit: ->
			@refs.dialog.setIsLoading true

			console.log "section index >>>>>>>>>>>>>>> ", @props.sectionIndex
			console.log "plan >>>>>>>>>>>>>>>>>>>>> ", @props.plan.toJS()
			console.log "newStatus >>>>>>>>>>>>>>>>>>>> ", @props.newStatus
			console.log "statusReason >>>>>>>>>>>>>>> ", @state.statusReason


			revisedPlan = @props.plan
			.setIn(['sections', @props.sectionIndex, 'status'], @props.newStatus)
			.setIn(['sections', @props.sectionIndex, 'statusReason'], @state.statusReason)
		
			@props.onSuccess revisedPlan, (=> @refs.dialog.setIsLoading(false) if @refs.dialog?), @props.onCancel

	return ModifySectionStatusDialog

module.exports = {load}
