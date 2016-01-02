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
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				metricDefinitions: Imm.List()
			}

		componentDidMount: ->
			metricDefinitionHeaders = null
			metricDefinitions = null

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
							console.error err
							console.error err.stack
							@setState {loadErrorType: 'io-error'}
							return

						CrashHandler.handle err
						return

					@setState {metricDefinitions}

		render: ->
			return R.div({className: 'metricDefinitionManagerTab'},
				R.div({className: 'header'},
					R.h1({}, "#{Term 'Metric'} Definitions")
				)
				R.div({className: 'main'},
					OrderableTable({
						tableData: @state.metricDefinitions
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
							}
							{
								name: "Options"
								nameIsVisible: false
								cellClass: 'optionsCell'
								buttons: [
									{
										className: 'btn btn-warning'
										text: null
										icon: 'wrench'
										dialog: DefineMetricDialog
										data: {
											onSuccess: @_addNewMetricDefinition
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
						onSuccess: @_addNewMetricDefinition
					},
						FaIcon('plus')
						" New #{Term 'Metric'}"
					)
				)
			)

		_addNewMetricDefinition: (newMetricDefinition) ->
			metricDefinitions = @state.metricDefinitions.push newMetricDefinition
			@setState {metricDefinitions}

		# _modifyEventType: (modifiedEventType) ->
		# 	originalEventType = @state.eventTypes
		# 	.find (eventType) -> eventType.get('id') is modifiedEventType.get('id')
			
		# 	eventTypeIndex = @state.eventTypes.indexOf originalEventType

		# 	@setState {eventTypes: @state.eventTypes.set(eventTypeIndex, modifiedEventType)}

	return MetricDefinitionManagerTab

module.exports = {load}
