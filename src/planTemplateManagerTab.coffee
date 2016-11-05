# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# The Plan tab on the client file page.

Async = require 'async'
Imm = require 'immutable'

Persist = require './persist'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	# TODO: Refactor to single require
	{BootstrapTable, TableHeaderColumn} = win.ReactBootstrapTable
	BootstrapTable = React.createFactory BootstrapTable
	TableHeaderColumn = React.createFactory TableHeaderColumn

	Term = require('./term')
	CrashHandler = require('./crashHandler').load(win)
	DialogLayer = require('./dialogLayer').load(win)
	Dialog = require('./dialog').load(win)

	{stripMetadata, FaIcon} = require('./utils').load(win)


	PlanTemplateManagerTab = React.createFactory React.createClass
		displayName: 'PlanTemplateManagerTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				dataIsReady: false
				planTemplates: Imm.List()
				displayInactive: null
			}

		componentWillMount: ->
			planTemplateHeaders = null
			planTemplates = null

			# Putting this in an Async Series since we will expand functionality soon.
			Async.series [
				(cb) =>
					ActiveSession.persist.planTemplates.list (err, result) =>
						if err
							cb err
							return

						planTemplateHeaders = result
						cb()
				(cb) =>
					Async.map planTemplateHeaders.toArray(), (planTemplateHeader, cb) =>
						planTemplateId = planTemplateHeader.get('id')

						ActiveSession.persist.planTemplates.readLatestRevisions planTemplateId, 1, cb
					, (err, results) =>
						if err
							cb err
							return

						planTemplates = Imm.List(results).map (planTemplate) -> stripMetadata planTemplate.get(0)
						cb()


			], (err) =>
					if err
						if err instanceof Persist.IOError
							Bootbox.alert "Please check your network connection and try again."
							return

						CrashHandler.handle err
						return

					@setState {
						dataIsReady: true
						planTemplates
					}

		render: ->
			planTemplates = @state.planTemplates

			# Determine inactive plan templates
			inactivePlanTemplates = planTemplates.filter (template) ->
				template.get('status') isnt 'default'

			hasInactivePlanTemplates = not inactivePlanTemplates.isEmpty()
			hasData = not @state.planTemplates.isEmpty()

			# UI Filters
			unless @state.displayInactive
				planTemplates = planTemplates.filter (template) ->
					template.get('status') is 'default'

			# Table display formats (TODO: extract to a tableWrapper component)
			# Convert 'default' -> 'active' for table display (TODO: Term)
			planTemplates = planTemplates.map (template) ->
				if template.get('status') is 'default'
					return template.set('status', 'active')

				return template


			return R.div({className: 'planTemplateManagerTab'},
				R.div({className: 'header'},
					R.h1({},
						R.div({className: 'optionsMenu'},
							## TODO: 'New Plan Template' button
							# OpenDialogLink({
							# 	className: 'btn btn-primary'
							# 	dialog: DefineMetricDialog
							# 	onSuccess: @_createMetric
							# },
							# 	FaIcon('plus')
							# 	" New "
							# )
							(if hasInactivePlanTemplates
								R.div({className: 'toggleInactive'},
									R.label({},
										"Show inactive (#{inactivePlanTemplates.size})"
										R.input({
											type: 'checkbox'
											checked: @state.displayInactive
											onClick: @_toggleDisplayInactive
										})
									)
								)
							)
						)
						Term 'Plan Templates'
					)
				)
				R.div({className: 'main'},
					(if @state.dataIsReady
						(if hasData
							R.div({className: 'responsiveTable animated fadeIn'},
								DialogLayer({
									ref: 'dialogLayer'
									planTemplates: @state.planTemplates
								},
									BootstrapTable({
										data: planTemplates.toJS()
										keyField: 'id'
										bordered: false
										options: {
											defaultSortName: 'name'
											defaultSortOrder: 'asc'
											onRowClick: (row) =>
												@refs.dialogLayer.open ModifyPlanTemplateDialog, {
													planTemplateId: row.id
													onSuccess: @_updatePlanTemplates
												}
											noDataText: "No #{Term 'plan templates'} to display"
										}
										trClassName: (row) -> 'inactive' if row.status isnt 'active'
									},
										# Filler column for display consistency
										TableHeaderColumn({
											dataField: 'id'
											className: 'colorKeyColumn'
											columnClassName: 'colorKeyColumn'
											dataFormat: -> null
										})
										TableHeaderColumn({
											dataField: 'name'
											className: [
												'rightPadding' unless @state.displayInactive
											].join ' '
											columnClassName: [
												'rightPadding' unless @state.displayInactive
											].join ' '
											dataSort: true
										}, "Template Name")

										TableHeaderColumn({
											dataField: 'description'
											className: [
												'descriptionColumn'
												'rightPadding' unless @state.displayInactive
											].join ' '
											columnClassName: [
												'rightPadding' unless @state.displayInactive
											].join ' '
											dataSort: false
										}, "Description")

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
											dataAlign: 'right'
											headerAlign: 'right'
											dataSort: true
											hidden: not @state.displayInactive
										}, "Status")
									)
								)
							)
						else
							R.div({className: 'noData'},
								R.span({className: 'animated fadeInUp'},
									"No #{Term 'plan templates'} exist yet"
								)
							)
						)
					)
				)
			)

		_toggleDisplayInactive: ->
			displayInactive = not @state.displayInactive
			@setState {displayInactive}

		_updatePlanTemplates: (updatedPlanTemplate) ->
			planTemplates = @state.planTemplates

			matchingPlanTemplate = planTemplates.find (template) ->
				template.get('id') is updatedPlanTemplate.get('id')

			planTemplateIndex = planTemplates.indexOf matchingPlanTemplate
			planTemplates = planTemplates.set planTemplateIndex, updatedPlanTemplate

			@setState {planTemplates}


	ModifyPlanTemplateDialog = React.createFactory React.createClass
		displayName: 'ModifyPlanTemplateDialog'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			planTemplateId: React.PropTypes.string.isRequired
		}

		getInitialState: ->
			return @_getTemplateDescription().toJS()

		componentWillMount: ->
			# Load the full planTemplate object
			planTemplateId = @props.planTemplateId

		render: ->
			planTemplate = @state.planTemplate

			return Dialog({
				ref: 'dialog'
				title: "Modify #{Term 'Plan Template'}"
				onClose: @props.onClose
			},
				R.div({id: 'modifyPlanTemplateDialog'},
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
						R.label({}, "Description")
						R.textArea({
							ref: 'definitionField'
							className: 'templateDescription'
							onChange: @_updateDescription
							value: @state.description
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Template Status"),
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
									'btn btn-' + if @state.status is 'cancelled'
										'danger'
									else
										'default'
								onClick: @_updateStatus
								value: 'cancelled'

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
						}, "Modify Template")
					)
				)
			)

		_cancel: ->
			@props.onCancel()

		_updateName: (event) ->
			@setState {name: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_updateStatus: (event) ->
			@setState {status: event.target.value}

		_getTemplateDescription: ->
			@props.planTemplates.find (template) =>
				template.get('id') is @props.planTemplateId

		_updateStatus: (event) ->
			@setState {status: event.target.value}

		_submit: ->
			unless @state.name.trim()
				Bootbox.alert "Template name is required"
				return

			unless @state.description.trim()
				Bootbox.alert "Template description is required"
				return

			# @refs.dialog.setIsLoading true

			newPlanTemplateRevision = Imm.fromJS {
				id: @_getTemplateDescription().get('id')
				name: @state.name.trim()
				description: @state.description.trim()
				sections: @state.sections
				status: @state.status
			}

			ActiveSession.persist.planTemplates.createRevision newPlanTemplateRevision, (err, result) =>
				# @refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				@props.onSuccess(result)


	return PlanTemplateManagerTab

module.exports = {load}