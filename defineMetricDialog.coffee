# A dialog for allowing the user to define (i.e. create) a new metric

Imm = require 'immutable'

Persist = require './persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	ExpandingTextArea = require('./expandingTextArea').load(win)

	DefineMetricDialog = React.createFactory React.createClass
		getInitialState: ->
			return {
				name: ''
				definition: ''
			}
		render: ->
			# This should be refactored into a generic "dialog" mixin when this
			# project needs its next type of dialog.

			return R.div({
				className: 'dialogContainer'
				onClick: @_onBackgroundClick
			},
				R.div({className: 'dialog panel panel-primary'},
					R.div({className: 'panel-heading'},
						R.h3({className: 'panel-title'}, "Define a new metric")
					)
					R.div({className: 'panel-body'},
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
								onClick: @props.onCancel
							}, "Cancel"),
							R.button({
								className: 'btn btn-primary'
								onClick: @_onSubmit
							}, "Create metric")
						)
					)
				)
			)
		_onBackgroundClick: (event) ->
			# If click was on background, not the dialog itself
			if event.target.classList.contains 'dialogContainer'
				@props.onCancel()
		_updateName: (event) ->
			@setState {name: event.target.value}
		_updateDefinition: (event) ->
			@setState {definition: event.target.value}
		_onSubmit: ->
			unless @state.name.trim()
				Bootbox.alert "Metric name is required"
				return

			unless @state.definition.trim()
				Bootbox.alert "Metric definition is required"
				return

			newMetric = Imm.fromJS {
				id: Persist.generateId()
				name: @state.name.trim()
				definition: @state.definition.trim()
			}

			Persist.Metric.create newMetric, (err, result) =>
				if err
					console.error err.stack
					Bootbox.alert "Error creating metric definition"
					return

				@props.onSuccess result.get('id')

	return DefineMetricDialog

module.exports = {load}
