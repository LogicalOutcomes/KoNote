# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
Imm = require 'immutable'

Persist = require './persist'
Config = require './config'
Term = require './term'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
	OrderableTable = require('./orderableTable').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	{FaIcon, showWhen, stripMetadata, renderName} = require('./utils').load(win)

	DefineMetricDialog = require('./defineMetricDialog').load(win)

	MetricDefinitionManagerTab = React.createFactory React.createClass
		displayName: 'MetricDefinitionManagerTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {
			metricDefinitions: Imm.List()
			displayDeactivated: false
		}

		componentWillMount: ->
			metricDefinitionHeaders = null
			metricDefinitions = Imm.List()

			Async.series [
				(cb) =>
					ActiveSession.persist.metrics.list (err, result) =>
						if err
							cb err
							return

						metricDefinitionHeaders = result
						cb()
				(cb) =>
					Async.map metricDefinitionHeaders.toArray(), (metricDefinitionHeader, cb) =>
						metricDefinitionId = metricDefinitionHeader.get('id')
						ActiveSession.persist.metrics.readLatestRevisions metricDefinitionId, 1, cb
					, (err, results) =>
						if err
							cb err
							return

						metricDefinitions = Imm.List(results)
						.map (metricDefinition) -> stripMetadata metricDefinition.first()

						cb()
			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert "Please check your network connection and try again."
						return

					CrashHandler.handle err
					return

				# Successfully loaded metric definitions
				@setState {metricDefinitions}

		render: ->
			isAdmin = global.ActiveSession.isAdmin()
			metrics = @state.metricDefinitions
			unless @state.displayDeactivated
				metrics = metrics.filter (metric) =>
					metric.get('status') is 'default'

			return R.div({className: 'metricDefinitionManagerTab'},
				R.div({className: 'header'},
					R.h1({},
						R.span({id: 'toggleDisplayDeactivated'},
							R.div({className: 'checkbox'},
								R.label({},
									R.input({
										type: 'checkbox'
										checked: @state.displayDeactivated
										onClick: @_toggleDisplayDeactivated
									})
									"Show deactivated"
								)
							)
						)
						"#{Term 'Metric'} Definitions"
					)
				)
				R.div({className: 'main'},
					OrderableTable({
						tableData: metrics
						noMatchesMessage: "No #{Term 'metrics'} defined yet"
						sortByData: ['name']
						columns: [
							{
								name: "Name"
								dataPath: ['name']
								cellClass: 'nameCell'
							}
							{
								name: "Definition"
								dataPath: ['definition']
								value: (dataPoint) ->
									definition = dataPoint.get('definition')

									if definition.length > 60
										return definition.substr(0, 59) + ' . . .'
									else
										return definition
							}
							{
								name: "Status"
								dataPath: ['status']
								cellClass: 'statusCell'
							}
							{
								name: "Options"
								nameIsVisible: false
								isDisabled: not isAdmin
								cellClass: 'optionsCell'
								buttons: [
									{
										className: 'btn btn-warning'
										text: null
										icon: 'wrench'
										dialog: ModifyMetricDialog
										data: {
											onSuccess: @_onModifyMetric
										}
									}
								]
							}
						]
					})
				)
				R.div({className: 'optionsMenu'},
					OpenDialogLink({
						className: 'btn btn-lg btn-primary'
						dialog: DefineMetricDialog
						onSuccess: @_onCreateMetric
					},
						FaIcon('plus')
						" New #{Term 'Metric'} Definition"
					)
				)
			)

		_onModifyMetric: (revisedMetric) ->
			originalMetric = @state.metricDefinitions.find (metric) ->
				metric.get('id') is revisedMetric.get('id')

			index = @state.metricDefinitions.indexOf originalMetric

			console.log "index", index

			metricDefinitions = @state.metricDefinitions.set index, revisedMetric
			@setState {metricDefinitions}

		_onCreateMetric: (createdMetric) ->
			metricDefinitions = @state.metricDefinitions.push createdMetric
			@setState {metricDefinitions}

		_toggleDisplayDeactivated: ->
			displayDeactivated = not @state.displayDeactivated
			@setState {displayDeactivated}

	ModifyMetricDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				name: @props.rowData.get('name')
				definition: @props.rowData.get('definition')
				status: @props.rowData.get('status')
			}

		componentDidMount: ->
			@refs.nameField.focus()

		render: ->
			Dialog({
				ref: 'dialog'
				title: "Modify #{Term 'Metric'} Definition"
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
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Definition")
						ExpandingTextArea({
							ref: 'definitionField'
							onChange: @_updateDefinition
							value: @state.definition
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Client File Status"),
						R.div({className: 'btn-toolbar'},
							R.button({
								className:
									if @state.status is 'default'
										'btn btn-success'
									else 'btn btn-default'
								onClick: @_updateStatus
								value: 'default'

								},
							"Default"
							)
							R.button({
								className:
									if @state.status is 'deactivated'
										'btn btn-warning'
									else 'btn btn-default'
								onClick: @_updateStatus
								value: 'deactivated'

								},
							"Deactivated"
							)
						)
					)
					R.div({className: 'btn-toolbar pull-right'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel
						}, "Cancel"),
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
						}, "Modify #{Term 'Metric'}")
					)
				)
			)

		_cancel: ->
			@props.onCancel()

		_updateName: (event) ->
			@setState {name: event.target.value}

		_updateDefinition: (event) ->
			@setState {definition: event.target.value}

		_updateStatus: (event) ->
			@setState {status: event.target.value}

		_submit: ->
			unless @state.name.trim()
				Bootbox.alert "#{Term 'Metric'} name is required"
				return

			unless @state.definition.trim()
				Bootbox.alert "#{Term 'Metric'} definition is required"
				return

			@refs.dialog.setIsLoading true

			newMetricRevision = Imm.fromJS {
				id: @props.rowData.get('id')
				name: @state.name.trim()
				definition: @state.definition.trim()
				status: @state.status
			}

			ActiveSession.persist.metrics.createRevision newMetricRevision, (err, result) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				@props.onSuccess(result)


	return MetricDefinitionManagerTab

module.exports = {load}
