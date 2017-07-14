# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# TODO: Consolidate with ModifyTopicStatusDialog / ModifyTopic...

Persist = require '../persist'


load = (win) ->
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('../crashHandler').load(win)
	Dialog = require('../dialog').load(win)


	ModifySectionStatusDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@refs.statusReasonField.focus()

		getInitialState: -> {
			statusReason: ''
		}

		render: ->
			Dialog({
				ref: 'dialog'
				title: @props.title
				onClose: @props.onClose
			},
				R.div({className: 'modifyTopicStatusDialog'},
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

			clientFile = @props.parentData
			index = clientFile.getIn(['chx', 'sections']).indexOf @props.data

			revisedCHx = clientFile.get('chx')
			.setIn(['sections', index, 'status'], @props.newStatus)
			.setIn(['sections', index, 'statusReason'], @state.statusReason)

			revisedClientFile = clientFile.set 'chx', revisedCHx

			ActiveSession.persist.clientFiles.createRevision revisedClientFile, (err, updatedClientFile) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							An error occurred.  Please check your network connection and try again.
						"""
						console.error err
						return

					CrashHandler.handle err
					return

				@props.onSuccess()


	return ModifySectionStatusDialog

module.exports = {load}
