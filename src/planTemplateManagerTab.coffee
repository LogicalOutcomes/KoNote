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
	R = React.DOM

	Config = require './config'
	Term = require('./term')
	CrashHandler = require('./crashHandler').load(win)
	OrderableTable = require('./orderableTable').load(win)
	{stripMetadata} = require('./utils').load(win)

	PlanTemplateManagerTab = React.createFactory React.createClass
		displayName: 'PlanTemplateManagerTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				planTemplateHeaders: Imm.List()
				planTemplates: null
			}

		componentWillMount: ->
			# Load planTemplate headers
			# putting this in an Async Series since we will expand functionality soon.
			
			planTemplateHeaders = null

			Async.series [
				(cb) =>
					ActiveSession.persist.planTemplates.list (err, result) =>
						if err
							cb err
							return

						planTemplateHeaders = result
						cb()

				# (cb) =>
				# 	Async.map planTemplateHeaders.toArray(), (planTemplateHeader, cb) =>
				# 		planTemplateId = planTemplateHeader.get('id')

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
			.filter (template) -> template.get('status') is 'default'

			return R.div({className: 'planTemplateManagerTab'},
				R.div({className: 'header'},
					R.h1({}, 'Plan Templates')
				)
				R.div({className: 'main'},
					OrderableTable({
						tableData: planTemplateHeaders
						noMatchesMessage: "No Plan Templates defined yet"
						sortByData: ['name']
						columns: [
							{
								name: "Template Name"
								dataPath: ['name']
								cellClass: 'nameCell'
							}
							{
								name: "Status"
								dataPath: ['status']
								cellClass: 'statusCell'
							}
							{
								name: "Options"
								nameIsVisible: false
								buttons: [
									{
										className: 'btn btn-danger'
										text: 'Deactivate'
										onClick: (planTemplateHeader) => @_deactivateTemplate.bind null, planTemplateHeader
									}

								]
							}
						]

					})
				)
			)

		_deactivateTemplate: (planTemplateHeader) ->
			console.log "planTemplateHeader in deactivate method", planTemplateHeader.toJS()
			
			planTemplate = null
			planTemplateId = planTemplateHeader.get('id')

			Async.series [
				(cb) =>
					Bootbox.confirm "Permanently deactivate Plan Template?", (result) =>
						if result
							cb()
						else 
							return
				(cb) =>
					ActiveSession.persist.planTemplates.readLatestRevisions planTemplateId, 1, (err, result) =>
						if err
							console.error err
							return

						planTemplate = stripMetadata result.get(0)
						console.log "planTemplate in deactivate method", planTemplate.toJS()
						cb()
				(cb) =>
					newTemplate = planTemplate.setIn(['status'], 'cancelled')
					console.log "newTemplate", newTemplate.toJS()

					ActiveSession.persist.planTemplates.createRevision newTemplate, (err, result) ->
						if err
							console.error err
							return
						cb()
			], (err) =>
				if err
					if err instanceof Persist.IOError
						Bootbox.alert "Please check your network connection and try again."
						return
				
				planTemplateIndex = @state.planTemplateHeaders.indexOf planTemplateHeader
				updatedPlanTemplateHeader = planTemplateHeader.setIn(['status'], 'cancelled')
				planTemplateHeaders = @state.planTemplateHeaders.set planTemplateIndex, updatedPlanTemplateHeader

				@setState {planTemplateHeaders}, ->
					Bootbox.alert "This Template has been deactivated."




	return PlanTemplateManagerTab

module.exports = {load}



