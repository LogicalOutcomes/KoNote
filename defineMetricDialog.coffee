# A dialog for allowing the user to define (i.e. create) a new metric

Imm = require 'immutable'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)

	DefineMetricDialog = React.createFactory React.createClass
		getInitialState: ->
			return {
				name: @props.metricQuery
				definition: ''
			}
		render: ->
			Dialog({
				title: "Define a new metric"
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
						})
					)
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel
						}, "Cancel"),
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
						}, "Create metric")
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
				Bootbox.alert "Metric name is required"
				return

			unless @state.definition.trim()
				Bootbox.alert "Metric definition is required"
				return

			newMetric = Imm.fromJS {
				name: @state.name.trim()
				definition: @state.definition.trim()
			}

			ActiveSession.persist.metrics.create newMetric, (err, result) =>
				if err
					CrashHandler.handle err
					return

				@props.onSuccess result.get('id')

	return DefineMetricDialog

module.exports = {load}
