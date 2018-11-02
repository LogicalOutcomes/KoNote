# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Dialog to define (i.e. create) a new metric

Imm = require 'immutable'

Persist = require './persist'
Term = require './term'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	{maxMetricNameLength} = require('./utils').load(win)


	DefineMetricDialog = React.createFactory React.createClass
		displayName: 'DefineMetricDialog'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		getInitialState: -> {
			name: @props.metricQuery or ''
			definition: ''
			customId: ''
		}

		componentDidMount: ->
			if @props.metricQuery?
				@refs.definitionField.focus()
			else
				@refs.nameField.focus()

		render: ->
			Dialog({
				ref: 'dialog'
				title: "Define New #{Term 'Metric'}"
				onClose: @_cancel
			},
				R.div({className: 'defineMetricDialog'},
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							ref: 'nameField'
							className: 'form-control'
							onChange: @_updateName
							value: @state.name
							maxLength: maxMetricNameLength
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Definition")
						R.textarea({
							className: 'form-control'
							ref: 'definitionField'
							onChange: @_updateDefinition
							value: @state.definition
							rows: 4
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "#{Term 'Custom Id'}"),
						R.input({
							ref: 'customIdField'
							className: 'form-control'
							onChange: @_updateCustomId
							value: @state.customId
							placeholder: "Unique ID (optional)"
							maxLength: maxMetricNameLength
						})
					)
					R.div({className: 'btn-toolbar pull-right'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel
						}, "Cancel"),
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
						}, "Create #{Term 'Metric'}")
					)
				)
			)

		_cancel: ->
			@props.onCancel()

		_updateName: (event) ->
			@setState {name: event.target.value}

		_updateDefinition: (event) ->
			@setState {definition: event.target.value}

		_updateCustomId: (event) ->
			@setState {customId: event.target.value}

		_submit: ->
			unless @state.name.trim()
				Bootbox.alert "#{Term 'Metric'} name is required"
				return

			unless @state.definition.trim()
				Bootbox.alert "#{Term 'Metric'} definition is required"
				return

			@refs.dialog.setIsLoading true

			ActiveSession.persist.metrics.list (err, result) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				# Avoid duplicate metrics
				# TODO: show the existing metric definition here to help the user decide how to continue
				existingMetric = result.find (match) => match.get('name').trim().toLowerCase() is @state.name.trim().toLowerCase()
				existingMetricId = result.find (match) => @state.customId and match.get('customId').trim() is @state.customId.trim()
				if existingMetric
					message = "A #{Term 'metric'} with this name already exists. Choose a new name to define this #{Term 'metric'}, or cancel and use the preexisting #{Term 'metric'}."
				if existingMetricId
					message = "A #{Term 'metric'} with this #{Term 'custom id'} already exists!"
				if existingMetric or existingMetricId
					Bootbox.alert {
						title: "Unable to Create #{Term 'Metric'}"
						message
					}
					.on 'hidden.bs.modal', =>
						@refs.nameField.focus()
					return
				else
					newMetric = Imm.fromJS {
						name: @state.name.trim()
						definition: @state.definition.trim()
						customId: @state.customId.trim()
						status: 'default'
					}

					ActiveSession.persist.metrics.create newMetric, (err, result) =>
						@refs.dialog.setIsLoading(false) if @refs.dialog?

						if err
							if err instanceof Persist.IOError
								Bootbox.alert """
									Please check your network connection and try again.
								"""
								return

							CrashHandler.handle err
							return

						@props.onSuccess result

	return DefineMetricDialog

module.exports = {load}
