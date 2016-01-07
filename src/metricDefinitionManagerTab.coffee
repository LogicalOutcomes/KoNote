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

		render: ->
			return R.div({className: 'metricDefinitionManagerTab'},
				R.div({className: 'header'},
					R.h1({}, "#{Term 'Metric'} Definitions")
				)
				R.div({className: 'main'},
					OrderableTable({
						tableData: @props.metricDefinitions
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
										dialog: ModifyMetricDialog
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
					},
						FaIcon('plus')
						" New #{Term 'Metric'}"
					)
				)
			)

	ModifyMetricDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				name: @props.rowData.get('name')
				definition: @props.rowData.get('definition')
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

				# New revision caught by page listeners
				@props.onSuccess()


	return MetricDefinitionManagerTab

module.exports = {load}
