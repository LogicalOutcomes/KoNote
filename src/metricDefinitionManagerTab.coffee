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

	# TODO: Refactor to single require
	{BootstrapTable, TableHeaderColumn} = win.ReactBootstrapTable
	BootstrapTable = React.createFactory BootstrapTable
	TableHeaderColumn = React.createFactory TableHeaderColumn

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	DefineMetricDialog = require('./defineMetricDialog').load(win)
	DialogLayer = require('./dialogLayer').load(win)

	{FaIcon, showWhen, stripMetadata, renderName} = require('./utils').load(win)


	MetricDefinitionManagerTab = React.createFactory React.createClass
		displayName: 'MetricDefinitionManagerTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {
			dataIsReady: false
			metricDefinitions: Imm.List()
			displayInactive: false
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

						metricDefinitions = Imm.List(results).map (metricDefinition) ->
							stripMetadata metricDefinition.first()

						cb()

			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert "Please check your network connection and try again."
						return

					CrashHandler.handle err
					return

				# Successfully loaded metric definitions
				@setState {
					dataIsReady: true
					metricDefinitions
				}

		render: ->
			isAdmin = global.ActiveSession.isAdmin()

			# Determine inactive metrics
			inactiveMetricDefinitions = @state.metricDefinitions.filter (metric) ->
				metric.get('status') isnt 'default'

			hasInactiveMetrics = not inactiveMetricDefinitions.isEmpty()
			hasData = not @state.metricDefinitions.isEmpty()

			# Configure table data
			tableData = @state.metricDefinitions

			# UI Filters
			unless @state.displayInactive
				tableData = tableData.filter (metric) -> metric.get('status') is 'default'

			# Table display formats (TODO: extract to a tableWrapper component)
			# Convert 'default' -> 'active' for table display (TODO: Term)
			tableData = tableData.map (metric) ->
				if metric.get('status') is 'default'
					return metric.set('status', 'active')

				return metric


			return R.div({className: 'metricDefinitionManagerTab'},
				R.div({className: 'header'},
					R.h1({},
						R.div({className: 'optionsMenu'},
							OpenDialogLink({
								className: 'btn btn-primary'
								dialog: DefineMetricDialog
								onSuccess: @_createMetric
							},
								FaIcon('plus')
								" New #{Term 'Metric Definition'}"
							)
							(if hasInactiveMetrics
								R.div({className: 'toggleInactive'},
									R.label({},
										"Show inactive (#{inactiveMetricDefinitions.size})"
										R.input({
											type: 'checkbox'
											checked: @state.displayInactive
											onClick: @_toggleDisplayInactive
										})
									)
								)
							)
						)
						"#{Term 'Metric Definitions'}"
					)
				)
				R.div({className: 'main'},
					(if @state.dataIsReady
						(if hasData
							R.div({className: 'responsiveTable animated fadeIn'},
								DialogLayer({
									ref: 'dialogLayer'
									metricDefinitions: @state.metricDefinitions
								},
									BootstrapTable({
										data: tableData.toJS()
										keyField: 'id'
										bordered: false
										options: {
											defaultSortName: 'name'
											defaultSortOrder: 'asc'
											onRowClick: ({id}) =>
												@refs.dialogLayer.open ModifyMetricDialog, {
													metricId: id
													onSuccess: @_modifyMetric
												}
											noDataText: "No #{Term 'metric definitions'} to display"
										}
										trClassName: (row) -> 'inactive' if row.status isnt 'active'
									},
										TableHeaderColumn({
											dataField: 'id'
											className: 'colorKeyColumn'
											columnClassName: 'colorKeyColumn'
											dataFormat: -> null
										})
										TableHeaderColumn({
											dataField: 'name'
											className: 'nameColumn'
											columnClassName: 'nameColumn'
											dataSort: true
										}, "#{Term 'Metric'} Name")
										TableHeaderColumn({
											dataField: 'definition'
											className: [
												'descriptionColumn'
												'rightPadding' unless @state.displayInactive
											].join ' '
											columnClassName: [
												'descriptionColumn'
												'rightPadding' unless @state.displayInactive
											].join ' '
										}, "Definition")
										TableHeaderColumn({
											dataField: 'status'
											className: [
												'statusColumn'
												'rightPadding' if @state.displayInactive
											].join ' '
											columnClassName: [
												'statusColumn'
												'rightPadding' if @state.displayInactive
											].join ' '
											dataSort: true
											hidden: not @state.displayInactive
											headerAlign: 'right'
											dataAlign: 'right'
										}, "Status")
									)
								)
							)
						else
							R.div({className: 'noData'},
								R.span({className: 'animated fadeInUp'},
									"No #{Term 'metric definitions'} exist yet"
								)
							)
						)
					)
				)
			)

		_modifyMetric: (revisedMetric) ->
			originalMetric = @state.metricDefinitions.find (metric) ->
				metric.get('id') is revisedMetric.get('id')

			index = @state.metricDefinitions.indexOf originalMetric

			metricDefinitions = @state.metricDefinitions.set index, revisedMetric
			@setState {metricDefinitions}

		_createMetric: (createdMetric) ->
			metricDefinitions = @state.metricDefinitions.push createdMetric
			@setState {metricDefinitions}

		_toggleDisplayInactive: ->
			displayInactive = not @state.displayInactive
			@setState {displayInactive}


	ModifyMetricDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return @_getMetricDefinition().toJS()

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
							maxLength: 128
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
						R.label({}, "#{Term 'Metric'} Status"),
						R.div({className: 'btn-toolbar'},
							R.button({
								className:
									if @state.status is 'default'
										'btn btn-success'
									else 'btn btn-default'
								onClick: @_updateStatus
								value: 'default'

								},
							"Active"
							)
							R.button({
								className:
									'btn btn-' + if @state.status is 'deactivated'
										'danger'
									else
										'default'
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

		_getMetricDefinition: ->
			@props.metricDefinitions.find (metric) =>
				metric.get('id') is @props.metricId

		_submit: ->
			unless @state.name.trim()
				Bootbox.alert "#{Term 'Metric'} name is required"
				return

			unless @state.definition.trim()
				Bootbox.alert "#{Term 'Metric'} definition is required"
				return

			@refs.dialog.setIsLoading true

			newMetricRevision = Imm.fromJS {
				id: @_getMetricDefinition().get('id')
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