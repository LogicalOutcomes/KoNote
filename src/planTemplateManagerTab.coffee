# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# The Plan tab on the client file page.

Async = require 'async'
Imm = require 'immutable'

Persist = require './persist'
Config = require './config'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	{PropTypes} = React
	R = React.DOM

	# TODO: Refactor to single require
	{BootstrapTable, TableHeaderColumn} = win.ReactBootstrapTable
	BootstrapTable = React.createFactory BootstrapTable
	TableHeaderColumn = React.createFactory TableHeaderColumn

	Config = require './config'
	Term = require('./term')
	CrashHandler = require('./crashHandler').load(win)
	OrderableTable = require('./orderableTable').load(win)
	DialogLayer = require('./dialogLayer').load(win)
	Dialog = require('./dialog').load(win)

	{stripMetadata, FaIcon} = require('./utils').load(win)


	PlanTemplateManagerTab = React.createFactory React.createClass
		displayName: 'PlanTemplateManagerTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				planTemplateHeaders: Imm.List()
				displayInactive: null
			}

		componentWillMount: ->
			planTemplateHeaders = null

			# Putting this in an Async Series since we will expand functionality soon.
			Async.series [
				(cb) =>
					ActiveSession.persist.planTemplates.list (err, result) =>
						if err
							cb err
							return

						planTemplateHeaders = result
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

					@setState {planTemplateHeaders}

		render: ->
			planTemplateHeaders = @state.planTemplateHeaders

			# Determine inactive plan templates
			inactivePlanTemplates = planTemplateHeaders.filter (template) ->
				template.get('status') isnt 'default'

			hasInactivePlanTemplates = not inactivePlanTemplates.isEmpty()

			# UI Filters
			unless @state.displayInactive
				planTemplateHeaders = planTemplateHeaders.filter (template) ->
					template.get('status') is 'default'

				console.log "planTemplateHeaders", planTemplateHeaders.toJS()

			# Table display formats (TODO: extract to a tableWrapper component)
			# Convert 'default' -> 'active' for table display (TODO: Term)
			planTemplateHeaders = planTemplateHeaders.map (template) ->
				if template.get('status') is 'default'
					return template.set('status', 'active')

				return template


			return R.div({className: 'planTemplateManagerTab'},
				R.div({className: 'header'},
					R.h1({},
						(if hasInactivePlanTemplates
							R.span({id: 'toggleDisplayInactive'},
								R.div({className: 'checkbox'},
									R.label({},
										R.input({
											type: 'checkbox'
											checked: @state.displayInactive
											onClick: @_toggleDisplayInactive
										})
										"Show inactive (#{inactivePlanTemplates.size})"
									)
								)
							)
						)
						'Plan Templates'
					)
				)
				R.div({className: 'main'},
					R.div({className: 'responsiveTable'},
						DialogLayer({
							ref: 'dialogLayer'
							planTemplateHeaders: @state.planTemplateHeaders
						},
							BootstrapTable({
								data: planTemplateHeaders.toJS()
								keyField: 'id'
								bordered: false
								options: {
									defaultSortName: 'name'
									defaultSortOrder: 'asc'
									onRowClick: (row) =>
										# TODO: Re-activation
										return unless row.status is 'active'

										@refs.dialogLayer.open ModifyPlanTemplateDialog, {
											planTemplateId: id
											onSuccess: @_updatePlanTemplateHeaders
										}
								}
								trClassName: (row) -> 'inactive' if row.status isnt 'active'
							},
								TableHeaderColumn({
									dataField: 'name'
									columnClassName: 'nameColumn'
									dataSort: true
								}, "Template Name")
								TableHeaderColumn({
									dataField: 'status'
									columnClassName: 'statusColumn'
									dataAlign: 'right'
									headerAlign: 'right'
									dataSort: true
									hidden: not @state.displayInactive
								}, "Status")
							)
						)
					)
				)
			)

		_toggleDisplayInactive: ->
			displayInactive = not @state.displayInactive
			@setState {displayInactive}

		_updatePlanTemplateHeaders: (updatedPlanTemplate) ->
			planTemplateHeaders = @state.planTemplateHeaders

			matchingPlanTemplate = planTemplateHeaders.find (template) ->
				template.get('id') is updatedPlanTemplate.get('id')

			planTemplateIndex = planTemplateHeaders.indexOf matchingPlanTemplate
			planTemplateHeaders = planTemplateHeaders.set planTemplateIndex, updatedPlanTemplate

			@setState {planTemplateHeaders}


	ModifyPlanTemplateDialog = React.createFactory React.createClass
		displayName: 'ModifyPlanTemplateDialog'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			planTemplateId: PropTypes.string.isRequired
		}

		getInitialState: -> {
			planTemplate: Imm.Map()
		}

		componentWillMount: ->
			# Load the full planTemplate object
			planTemplateId = @props.planTemplateId

			ActiveSession.persist.planTemplates.readLatestRevisions planTemplateId, 1, (err, result) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert "Please check your network connection and try again."
						return

					CrashHandler.handle(err)
					return

				planTemplate = stripMetadata result.get(0)
				@setState {planTemplate}

		render: ->
			planTemplate = @state.planTemplate
			planTemplateName = planTemplate.get('name')

			return Dialog({
				ref: 'dialog'
				title: "Modify #{Term 'Plan Template'}"
				onClose: @props.onClose
			},
				R.div({id: 'modifyPlanTemplateDialog'},
					R.h4({}, planTemplateName)
					R.hr({})
					R.div({}
						R.button({
							className: 'btn btn-danger btn-block'
							onClick: @_handleDeactivate.bind null, planTemplateName
						},
							"Cancel"
							" "
							FaIcon('ban')
						)
					)
				)
			)

		_handleDeactivate: (planTemplateName) ->
			Bootbox.confirm """
				Permanently cancel #{Term 'plan template'}: <strong>#{planTemplateName}</strong>?
			""", (ok) =>
				if ok then @_updatePlanTemplateStatus('cancelled')

		_updatePlanTemplateStatus: (newStatus) ->
			planTemplateId = @state.planTemplate.get('id')
			updatedPlanTemplate = null

			Async.series [
				(cb) =>
					ActiveSession.persist.planTemplates.readLatestRevisions planTemplateId, 1, (err, result) =>
						if err
							cb err
							return

						planTemplate = stripMetadata result.get(0)
						cb()

				(cb) =>
					updatedPlanTemplate = planTemplate.set('status', newStatus)

					ActiveSession.persist.planTemplates.createRevision updatedPlanTemplate, (err, result) =>
						if err
							cb err
							return

						updatedPlanTemplate = result
						cb()

			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert "Please check your network connection and try again."
						return

					CrashHandler.handle err
					return


				# Pass updated planTemplate back to parent
				# It's ok for now that we're not passing back a header
				@props.onSuccess(updatedPlanTemplate)


	return PlanTemplateManagerTab

module.exports = {load}