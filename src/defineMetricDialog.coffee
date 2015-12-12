# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A dialog for allowing the user to define (i.e. create) a new metric

Imm = require 'immutable'

Persist = require './persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	Config = require('./config')
	Term = require('./term')
	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	{FaIcon, showWhen} = require('./utils').load(win)

	DefineMetricDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				name: @props.metricQuery
				definition: ''
			}
		componentDidMount: ->
			React.findDOMNode(@refs.metricDefinition).focus()
			
		render: ->
			Dialog({
				title: "Define a new #{Term 'metric'}"
				onClose: @_cancel
			},
				R.div({className: 'defineMetricDialog'},
					R.div({className: 'form-group'},
						R.label({}, "Name"),
						R.input({
							className: 'form-control'
							onChange: @_updateName
							value: @state.name
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Definition"),
						ExpandingTextArea({
							onChange: @_updateDefinition
							value: @state.definition
							ref: 'metricDefinition'
						})
					)
					R.div({className: 'alert alert-warning'},
						FaIcon('warning'),
						"The name and definition of a #{Term 'metric'} cannot be changed ",
						"after it has been created."
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel
						}, "Cancel"),
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
						}, "Create #{Term 'metric'}")
					)
				)
			)
		_cancel: ->
			@props.onCancel()
		_updateName: (event) ->
			@setState {name: event.target.value}
		_updateDefinition: (event) ->
			@setState {definition: event.target.value}
		_submit: ->
			unless @state.name.trim()
				Bootbox.alert "#{Term 'Metric'} name is required"
				return

			unless @state.definition.trim()
				Bootbox.alert "#{Term 'Metric'} definition is required"
				return

			newMetric = Imm.fromJS {
				name: @state.name.trim()
				definition: @state.definition.trim()
			}

			ActiveSession.persist.metrics.create newMetric, (err, result) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				@props.onSuccess result.get('id')

	return DefineMetricDialog

module.exports = {load}
