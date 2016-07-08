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
	Dialog = require('./dialog').load(win)
	OrderableTable = require('./orderableTable').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	Spinner = require('./spinner').load(win)
	{FaIcon, stripMetadata, showWhen} = require('./utils').load(win)

	PlanTemplateManagerTab = React.createFactory React.createClass
		displayName: 'PlanTemplateManagerTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				planTemplateHeaders: null
				planTemplates: null

			}

		componentWillMount: ->
			# Load planTemplate headers
			planTemplateHeaders = null

			# putting this in an Async Series since we will expand functionality soon.


			Async.series [
				(cb) =>
					ActiveSession.persist.planTemplates.list (err, result) =>
						if err
							cb err
							return

						planTemplateHeaders = result
						cb()

						console.log "planTemplateHeaders", planTemplateHeaders.toJS()
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
			planTemplateId = planTemplateHeader.get('id')
			planTemplate = null

			ActiveSession.persist.planTemplates.readLatestRevisions planTemplateId, 1, (err, result) =>
				if err
					console.error err
					return

				planTemplate = stripMetadata result.get(0)
				console.log "planTemplate in deactivate method", planTemplate.toJS()

				newTemplate = planTemplate.setIn(['status'], 'cancelled')
				console.log "newTemplate", newTemplate.toJS()

				ActiveSession.persist.planTemplates.createRevision newTemplate, (err, result) ->
					if err
						console.error err
						return






	return PlanTemplateManagerTab

module.exports = {load}



