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
	$ = require 'jquery'
	Bootbox = require 'bootbox'

	React = require 'react'
	R = React.DOM
	PureRenderMixin = require 'react-addons-pure-render-mixin'

	B = require 'react-bootstrap'

	CrashHandler = require('./crashHandler').load(win)
	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
	ProgramBubbles = require('./programBubbles').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)

	{renderName, renderRecordId, FaIcon, stripMetadata} = require('./utils').load(win)

	CreateClientFileDialog = React.createFactory React.createClass
		displayName: 'CreateClientFileDialog'
		mixins: [PureRenderMixin]

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
			ActiveSession.persist.planTemplates.list (err, result) =>
				if err
					CrashHandler.handle err
					return

				planTemplateHeaders = result
				.filter (template) -> template.get('status') is 'default'

				@setState {planTemplateHeaders}

		render: ->
			formIsValid = @_formIsValid()
			selectedPlanTemplateHeaders = @state.planTemplateHeaders.find (template) => template.get('id') is @state.templateId
			recordIdIsRequired = Config.clientFileRecordId.isRequired

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
							maxLength: 35
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Middle Name"),
						R.input({
							className: 'form-control'
							onChange: @_updateMiddleName
							value: @state.middleName
							placeholder: "(optional)"
							maxLength: 35
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Last Name"),
						R.input({
							className: 'form-control'
							onChange: @_updateLastName
							value: @state.lastName
							onKeyDown: @_onEnterKeyDown
							maxLength: 35
						})
					)

					(unless @props.programs.isEmpty()
						R.div({className: 'form-group'},
							R.label({}, "Assign to #{Term 'Program'}(s)")
							R.div({id: 'programsContainer'},
								(@props.programs
								.filter (program) =>
									program.get('status') is 'default'
								.map (program) =>
									isSelected = @state.programIds.contains(program.get('id'))

									R.button({
										className: 'btn btn-default programOptionButton'
										onClick:
											(if isSelected then @_removeFromPrograms else @_pushToPrograms)
											.bind null, program.get('id')
										key: program.get('id')
									},
										ColorKeyBubble({
											colorKeyHex: program.get('colorKeyHex')
											popover: {
												title: program.get('name')
												content: program.get('description')
											}
											icon: 'check' if isSelected
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
								placeholder: "(optional)" unless recordIdIsRequired
								onKeyDown: @_onEnterKeyDown
								maxLength: 23
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
							disabled: not formIsValid
						}, "Create #{Term 'Client File'}")
					)
				)
			)

		_formIsValid: ->
			recordIdIsRequired = Config.clientFileRecordId.isRequired
			if recordIdIsRequired
				return @state.firstName and @state.lastName and @state.recordId
			else
				return @state.firstName and @state.lastName
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
			if event.which is 13 and @_formIsValid()
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
			  status: 'active'
			  plan: {
			    sections: []
			  }
			  detailUnits: []
			}

			clientFileHeaders = null
			newClientFileObj = null

			newClientFile = null
			selectedPlanTemplate = null
			templateSections = null

			Async.series [
				(cb) =>
					# First pull the latest clientFile headers for uniqueness comparison
					ActiveSession.persist.clientFiles.list (err, result) =>
						if err
							cb err
							return

						clientFileHeaders = result
						cb()

				(cb) =>
						# Enforce uniqueness of clientFileRecordId
						clientsWithRecordId = clientFileHeaders.filter (clientFile) ->
							clientFile.get('recordId') and (clientFile.get('recordId') is recordId)

						return cb() if clientsWithRecordId.isEmpty()


						clientsByStatus = clientsWithRecordId.groupBy (clientFile) -> clientFile.get('status')

						clientList = clientsByStatus
						.map (clients, status) ->
							clients.map (clientFile) -> "<b>#{renderName clientFile.get('clientName')}</b> (#{status})"
						.flatten()
						.toList()

						Bootbox.confirm """
							The #{renderRecordId recordId} is already in use by #{clientList.toJS().join(', ')}.
							Would you like to continue creating a duplicate #{Config.clientFileRecordId.label}?
						""", (ok) ->
							if ok then cb() else cb('CANCEL')

					(cb) =>
						# Warn if first & last name already used, but may continue
						matchingClientName = clientFileHeaders.find (clientFile) ->
							sameFirstName = clientFile.getIn(['clientName', 'first']).toLowerCase() is first.toLowerCase()
							sameLastName = clientFile.getIn(['clientName', 'last']).toLowerCase()  is last.toLowerCase()
							return sameFirstName and sameLastName

						return cb() unless matchingClientName


						matchingClientRecordId = if Config.clientFileRecordId.isEnabled
							" #{renderRecordId matchingClientName.get('recordId')}"
						else
							""

						Bootbox.confirm """
							The name \"#{first} #{last}\" matches an existing #{Term 'client file'}
							\"<b>#{renderName matchingClientName.get('clientName')}</b>\" #{matchingClientRecordId}).
							Would you like to create this new #{Term 'client file'} anyway?
						""", (ok) ->
							if ok then cb() else cb('CANCEL')

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
					return cb() unless @state.templateId

					# Apply template if template selected
					selectedPlanTemplateHeader = @state.planTemplateHeaders.find (template) =>
						template.get('id') is @state.templateId

					cb() unless selectedPlanTemplateHeader?

					ActiveSession.persist.planTemplates.readLatestRevisions @state.templateId, 1, (err, result) ->
						if err
							cb err
							return

						selectedPlanTemplate = stripMetadata result.get(0)
						cb()

				(cb) =>
					return cb() unless @state.templateId

					templateSections = selectedPlanTemplate.get('sections').map (section) ->
						templateTargets = section.get('targets').map (target) ->
							Imm.fromJS {
								clientFileId: newClientFile.get('id')
								name: target.get('name')
								description: target.get('description')
								status: 'default'
								metricIds: target.get('metricIds')
							}

						return section.set 'targets', templateTargets

					Async.map templateSections.toArray(), (section, cb) ->
						Async.map section.get('targets').toArray(), (target, cb) ->
							global.ActiveSession.persist.planTargets.create target, (err, result) ->
								if err
									cb err
									return

								cb null, result.get('id')

						, (err, results) ->
							if err
								cb err
								return

							targetIds = Imm.List(results)

							newSection = Imm.fromJS {
								id: Persist.generateId()
								name: section.get('name')
								targetIds: results
								status: 'default'
							}

							cb null, newSection

					, (err, results) ->
						if err
							cb err
							return

						templateSections = Imm.List(results)
						cb()

				(cb) =>
					return cb() unless @state.templateId

					clientFile = newClientFile.setIn(['plan', 'sections'], templateSections)

					global.ActiveSession.persist.clientFiles.createRevision clientFile, cb

			], (err) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?

				if err
					if err is 'CANCEL' then return

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
