# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Dialog to create a new client file

_ = require 'underscore'
Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'

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


	{renderName, renderRecordId, FaIcon, stripMetadata} = require('./utils').load(win)


	CreateClientFileDialog = React.createFactory React.createClass
		displayName: 'CreateClientFileDialog'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			@refs.firstNameField.focus()
			@_loadData()

		getInitialState: ->
			return {
				birthDay: ''
				birthMonth: ''
				birthYear: ''
				firstName: ''
				middleName: ''
				lastName: ''
				recordId: ''
				programId: ''
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
			recordIdIsRequired = Config.clientFileRecordId.isRequired

			Dialog({
				ref: 'dialog'
				title: "New #{Term 'Client File'}"
				onClose: @props.onClose
			},
				R.div({className: 'createClientFileDialog form-horizontal'},
					# R.div({className: 'col-xs-8 col-xs-offset-4'}, 'New Client File')
					R.div({className: 'form-group'},
						R.label({className: 'col-sm-4 control-label'}, "First Name"),
						R.div({className: 'col-sm-8'},
							R.input({
								ref: 'firstNameField'
								className: 'form-control'
								onChange: @_updateFirstName
								value: @state.firstName
								onKeyDown: @_onEnterKeyDown
								maxLength: 35
							})
						)
					)
					R.div({className: 'form-group'},
						R.label({className: 'col-sm-4 control-label'}, "Middle Name"),
						R.div({className: 'col-sm-8'},
							R.input({
								className: 'form-control'
								onChange: @_updateMiddleName
								value: @state.middleName
								placeholder: "(optional)"
								maxLength: 35
							})
						)
					)
					R.div({className: 'form-group'},
						R.label({className: 'col-sm-4 control-label'}, "Last Name"),
						R.div({className: 'col-sm-8'},
							R.input({
								className: 'form-control'
								onChange: @_updateLastName
								value: @state.lastName
								onKeyDown: @_onEnterKeyDown
								maxLength: 35
							})
						)
					)

					(if Config.clientFileRecordId.isEnabled
						R.div({className: 'form-group'},
							R.label({className: 'col-sm-4 control-label'}, Config.clientFileRecordId.label),
							R.div({className: 'col-sm-8'},
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
					)
					R.div({className: "form-group"},
						R.label({className: 'col-sm-4 control-label'}, "Birthday")
						R.div({className: 'col-sm-4'},
							R.select({
								className: 'form-control'
								onChange: @_updateBirthMonth
								value: @state.birthMonth
							},
								R.option({
									value: ''
									# hidden: true
								}, "Month")
								(months = Moment.monthsShort()
								months.map (month) =>
									R.option({
											key: month
											value: month
										},
										month
									)
								)
							)
						)
						R.div({className: 'col-sm-2 birthday'},
							R.input({
								className: 'form-control'
								onChange: @_updateBirthDay
								value: @state.birthDay
								placeholder: "Day"
								onKeyDown: @_onEnterKeyDown
								maxLength: 2
							})
						)
						R.div({className: 'col-sm-2 birthday'},
							R.input({
								className: 'form-control'
								onChange: @_updateBirthYear
								value: @state.birthYear
								placeholder: "Year"
								onKeyDown: @_onEnterKeyDown
								maxLength: 4
							})
						)
					)

					(unless @props.programsById.isEmpty()
						R.div({className: 'form-group'},
							R.label({className: 'col-sm-4 control-label'}, "#{Term 'Program'}"),
							R.div({className: 'col-sm-8'},
								R.select({
									className: 'form-control'
									onChange: @_updateProgramId
									value: @state.programId
								},
									R.option({value: ''}, "Select a #{Term 'client'} #{Term 'program'}")
									(@props.programsById
										.valueSeq()
										.sortBy((val, key) => val.get('name'))
										.map (program) ->
											R.option({
												key: program.get('id')
												value: program.get('id')
											},
												program.get('name')
											)
									)
								)
							)
						)
					)

					(unless @state.planTemplateHeaders.isEmpty()
						R.div({className: 'form-group'},
							R.label({className: 'col-sm-4 control-label'}, "#{Term 'Plan'} Template"),
							R.div({className: 'col-sm-8'},
								R.select({
									className: 'form-control'
									onChange: @_updatePlanTemplate
									value: @state.templateId
								},
									R.option({value: ''}, "Select a #{Term 'plan'} #{Term 'template'}")
									(@state.planTemplateHeaders.sortBy((val, key) => val.get('name')).map (planTemplateHeader) =>
										R.option({
												key: planTemplateHeader.get('id')
												value: planTemplateHeader.get('id')
											},
											planTemplateHeader.get('name')
										)
									)
								)
							)
						)
					)

					R.div({className: 'col-sm-8 col-sm-offset-4'},
						R.button({
							className: 'btn btn-primary'
							onClick: @_submit
							disabled: not formIsValid
						}, "Create #{Term 'Client File'}")
					)
				)
			)

		_formIsValid: ->
			# dob field must be all or none
			birthday = true
			if @state.birthDay or @state.birthMonth or @state.birthYear
				unless @state.birthDay and @state.birthMonth and @state.birthYear and
					Moment(@state.birthYear + @state.birthMonth + @state.birthDay, 'YYYYMMMD', true).isValid()
						birthday = false

			recordIdIsRequired = Config.clientFileRecordId.isRequired
			if recordIdIsRequired
				return birthday and @state.firstName and @state.lastName and @state.recordId
			else
				return birthday and @state.firstName and @state.lastName
		_cancel: ->
			@props.onCancel()

		_updateFirstName: (event) ->
			@setState {firstName: event.target.value}

		_updateMiddleName: (event) ->
			@setState {middleName: event.target.value}

		_updateLastName: (event) ->
			@setState {lastName: event.target.value}

		_updateBirthMonth: (event) ->
			@setState {birthMonth: event.target.value}

		_updateBirthDay: (event) ->
			@setState {birthDay: event.target.value.replace(/[^0-9]/g,'')}

		_updateBirthYear: (event) ->
			@setState {birthYear: event.target.value.replace(/[^0-9]/g,'')}

		_updateRecordId: (event) ->
			@setState {recordId: event.target.value}

		_updateProgramId: (event) ->
			 @setState {programId: event.target.value}

		_updatePlanTemplate: (event) ->
			@setState {templateId: event.target.value}

		_onEnterKeyDown: (event) ->
			if event.which is 13 and @_formIsValid()
				@_submit()

		_submit: ->
			@refs.dialog.setIsLoading(true)

			first = @state.firstName.trim()
			middle = @state.middleName.trim()
			last = @state.lastName.trim()
			recordId = @state.recordId.trim()

			if @state.birthYear and @state.birthMonth and @state.birthDay
				birthDate = Moment(@state.birthYear + @state.birthMonth + @state.birthDay, 'YYYYMMMD', true).format('YYYYMMMDD')
			else
				birthDate = ''

			clientFile = Imm.fromJS {
			  clientName: {first, middle, last}
			  recordId: recordId
			  status: 'active'
			  birthDate
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
			programId = null

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
						clients.map (clientFile) ->
							R.span({key: clientFile.get('id')},
								R.b({}, renderName clientFile.get('clientName')),
								" (", status, ")"
							)
					.flatten()
					.toList()

					Bootbox.dialog {
						title: "Error: duplicate ID"
						message: R.div({},
							renderRecordId(recordId),
							" is already in use by ",
							clientList.interpose(', '),
							"."
							R.br(), R.br(),
							"The #{Term 'client file'} was not created."
						)
						buttons: {
							createAnyway: {
								label: 'Create anyway (not recommended)'
								className: 'btn-default'
								callback: =>
									cb()
							},
							ok: {
								label: R.span({style: {
									paddingLeft: '20px',
									paddingRight: '20px',
								}}, 'OK')
								className: 'btn-primary'
								callback: =>
									cb('CANCEL')
							}
						}
						onEscape: ->
							cb('CANCEL')
					}

				(cb) =>
					# Warn if first & last name already used, but may continue
					matchingClientFiles = clientFileHeaders.filter (clientFile) ->
						sameFirstName = clientFile.getIn(['clientName', 'first']).toLowerCase() is first.toLowerCase()
						sameLastName = clientFile.getIn(['clientName', 'last']).toLowerCase()  is last.toLowerCase()
						return sameFirstName and sameLastName

					if matchingClientFiles.isEmpty()
						cb()
						return

					clientFilesElems = matchingClientFiles.map (clientFileHeader) ->
						R.span({},
							R.strong({}, renderName(clientFileHeader.get('clientName'))),
							(if Config.clientFileRecordId.isEnabled and clientFileHeader.get('recordId')
								R.span({},
									' (', renderRecordId(clientFileHeader.get('recordId')), ')'
								)
							)
						)

					Bootbox.dialog {
						title: "Error: duplicate name"
						message: R.div({},
							"There is already a #{Term 'client file'} under the name ",
							"\"#{first} #{last}\":", R.br()
							clientFilesElems.interpose(R.br()),
							R.br(), R.br(),
							"The #{Term 'client file'} was not created."
						)
						buttons: {
							createAnyway: {
								label: 'Create anyway'
								className: 'btn-default'
								callback: =>
									cb()
							},
							ok: {
								label: R.span({style: {
									paddingLeft: '20px',
									paddingRight: '20px',
								}}, 'OK')
								className: 'btn-primary'
								callback: =>
									cb('CANCEL')
							}
						}
						onEscape: ->
							cb('CANCEL')
					}

				(cb) =>
					# Create the clientFile,
					global.ActiveSession.persist.clientFiles.create clientFile, (err, result) =>
						if err
							cb err
							return

						newClientFile = result
						cb()

				(cb) =>
					return cb() unless @state.programId
					# Build the link object
					link = Imm.fromJS {
							clientFileId: newClientFile.get('id')
							status: 'enrolled'
							programId: @state.programId
						}

					global.ActiveSession.persist.clientFileProgramLinks.create link, cb


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
								programId: section.get('programId')
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
