# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A dialog for allowing the user to create a new client file
Async = require 'async'

Persist = require './persist'
Imm = require 'immutable'
Config = require './config'
Term = require './term'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	B = require('./utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')
	{FaIcon, stripMetadata} = require('./utils').load(win)

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
	ProgramBubbles = require('./programBubbles').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)

	CreateClientFileDialog = React.createFactory React.createClass
		displayName: 'CreateClientFileDialog'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@refs.firstNameField.focus()
			@_loadData()

		getInitialState: ->
			return {
				firstName: ''
				middleName: ''
				lastName: ''
				recordId: ''
				programIds: Imm.List()
				clientfileId: ''
				templateId: ''
				planTemplateHeaders: Imm.List()
			}

		_loadData: ->
			planTemplateHeaders = null
			console.log "Loading Data >>>>>>>>>>>>>>>>"
			ActiveSession.persist.planTemplates.list (err, result) =>
				if err
					cb err
					return

				planTemplateHeaders = result
				console.log "planTempHeaders >>>>>", planTemplateHeaders.toJS()

				@setState {planTemplateHeaders}

		render: ->
			selectedPlanTemplateHeaders = @state.planTemplateHeaders.find (template) => template.get('id') is @state.templateId
	
			# if selectedPlanTemplateHeaders?
			# 	console.log "selectedPlanTemplateHeaders >>>>", selectedPlanTemplateHeaders.toJS()
			# 	ActiveSession.persist.planTemplates.readRevisions @state.templateId, (err, result) =>
			# 		if err
			# 			cb err
			# 			return
			# 		selectedPlanTemplate = result
			# 		console.log "selectedPlanTemplate >>>>>>>>>>>>>", selectedPlanTemplate.toJS()

			Dialog({
				ref: 'dialog'
				title: "Create New #{Term 'Client File'}"
				onClose: @props.onClose
			},
				R.div({className: 'createClientFileDialog'},
					R.div({className: 'form-group'},
						R.label({}, "First Name"),
						R.input({
							ref: 'firstNameField'
							className: 'form-control'
							onChange: @_updateFirstName
							value: @state.firstName
							onKeyDown: @_onEnterKeyDown
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Middle Name"),
						R.input({
							className: 'form-control'
							onChange: @_updateMiddleName
							value: @state.middleName
							placeholder: "(optional)"
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Last Name"),
						R.input({
							className: 'form-control'
							onChange: @_updateLastName
							value: @state.lastName
							onKeyDown: @_onEnterKeyDown
						})
					)
					
					(unless @props.programs.isEmpty()
						R.div({className: 'form-group'},
							R.label({}, "Assign to #{Term 'Program'}(s)")
							R.div({id: 'programsContainer'},
								(@props.programs.map (program) =>
									isSelected = @state.programIds.contains(program.get('id'))
									R.button({
										className: 'btn btn-default programOptionButton'
										onClick: 
											(if isSelected then @_removeFromPrograms else @_pushToPrograms)
											.bind null, program.get('id')
										key: program.get('id')
										value: program.get('id')
										},
										ColorKeyBubble({
											isSelected
											data: program
											key: program.get('id')
										})
										program.get('name')
									)
								)
							)
						)
					)

					unless @state.planTemplateHeaders.isEmpty()
						R.div({className: 'form-group'},
							R.label({}, "Select Plan Template"),
							R.div({className: "template-container"}

								B.DropdownButton({
									title: if selectedPlanTemplateHeaders? then selectedPlanTemplateHeaders.get('name') else "No Template"
								},
									if selectedPlanTemplateHeaders?
										[
											B.MenuItem({
												onClick: @_updatePlanTemplate.bind null, ''
											},
												"None "
												FaIcon('ban')
											)
											B.MenuItem({divider: true})
										]
									(@state.planTemplateHeaders.map (planTemplateHeader) =>
										B.MenuItem({
											key: planTemplateHeader.get('id')
											onClick: @_updatePlanTemplate.bind null, planTemplateHeader.get('id')
										},
											R.div({
												onclick: @_updatePlanTemplate.bind null, planTemplateHeader.get('id')
											},
												planTemplateHeader.get('name')

											)
										)
									)
								)
							)
						)

					(if Config.clientFileRecordId.isEnabled
						R.div({className: 'form-group'},
							R.label({}, Config.clientFileRecordId.label),
							R.input({
								className: 'form-control'
								onChange: @_updateRecordId
								value: @state.recordId
								placeholder: "(optional)"
								onKeyDown: @_onEnterKeyDown
							})
						)
					)

					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @_cancel							
						}, "Cancel")
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
							disabled: not @state.firstName or not @state.lastName
						}, "Create #{Term 'Client File'}")
					)
				)
			)

		_cancel: ->
			@props.onCancel()

		_updateFirstName: (event) ->
			@setState {firstName: event.target.value}

		_updateMiddleName: (event) ->
			@setState {middleName: event.target.value}

		_updateLastName: (event) ->
			@setState {lastName: event.target.value}

		_updateRecordId: (event) ->
			@setState {recordId: event.target.value}

		_pushToPrograms: (programId) ->
			programIds = @state.programIds.push programId
			@setState {programIds}

		_removeFromPrograms: (programId) ->
			index = @state.programIds.indexOf(programId)
			programIds = @state.programIds.splice(index, 1)
			@setState {programIds}

		_updatePlanTemplate: (templateId) ->
			@setState {templateId}

		_onEnterKeyDown: (event) ->
			if event.which is 13 and @state.firstName and @state.lastName
				@_submit()

		_submit: ->
			@refs.dialog.setIsLoading(true)

			first = @state.firstName
			middle = @state.middleName
			last = @state.lastName
			recordId = @state.recordId		

			clientFile = Imm.fromJS {
			  clientName: {first, middle, last}
			  recordId: recordId
			  plan: {
			    sections: []
			  }
			}			

			newClientFileObj = null

			Async.series [
				(cb) =>
					# Create the clientFile, 
					global.ActiveSession.persist.clientFiles.create clientFile, (err, result) =>
						if err
							cb err
							return

						newClientFile = result
						cb()
				(cb) =>
					# Build the link objects
					clientFileProgramLinks = @state.programIds.map (programId) ->
						Imm.fromJS {
							clientFileId: newClientFile.get('id')
							status: 'enrolled'
							programId
						}

					# Build every link in list asyncronously, then cb
					Async.each clientFileProgramLinks.toArray(), (link, cb) ->
						global.ActiveSession.persist.clientFileProgramLinks.create link, cb
					, cb
				(cb) =>

					# Apply template if template selected
					console.log "Applying Template: step 1 >>>"
					selectedPlanTemplateHeaders = @state.planTemplateHeaders.find (template) => template.get('id') is @state.templateId
					
					if selectedPlanTemplateHeaders?
						
						console.log "selectedPlanTemplateHeaders IN SERIES >>>>", selectedPlanTemplateHeaders.toJS()
						
						ActiveSession.persist.planTemplates.readLatestRevisions @state.templateId, 1, (err, result) ->
							if err
								cb err
								return
							selectedPlanTemplate = stripMetadata Imm.List(result).get(0)
							console.log "selectedPlanTemplate upon reading revision >>>>>>>", selectedPlanTemplate.toJS()
							cb()
					else cb()
				(cb) =>
						console.log "Applying Template: step 2 >>>"
						console.log "selectedPlanTemplate IN SERIES step 2 >>>>", selectedPlanTemplate.toJS()

						selectedPlanTemplate.get('sections').forEach (templateSection) =>
							targetIds = []
							templateSection.get('targets').forEach (templateTarget) =>
								target = Imm.fromJS {
									clientFileId: newClientFile.get('id')
									name: templateTarget.get('id')
									description: templateTarget.get('description')
									status: 'default'
									metricIds: templateTarget.get('metricIds')
								}
								# Creating each target
								global.ActiveSession.persist.planTargets.create target, (err, result) =>
									if err
										cb err
										return
									newTarget = result
								
								targetIds.push newTarget.get('id')

							# Creating each section
							section = Imm.fromJS {
								id: generateId()
								name: templateSection.get('name')
								targetIds
								status: 'default'
							}

							clientFile = newClientFile.setIn(['plan', 'sections'], section)

						global.ActiveSession.persist.clientFiles.createRevision clientFile, (err, result) ->
							if err
								cb err
								return
							cb()

			], (err) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err instanceof Persist.IOError
						console.error err
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				# UI will be auto-updated with new file/links by page listeners
				@props.onSuccess()

						
	return CreateClientFileDialog

module.exports = {load}
