# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# The Client Information tab on the client file page.

Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'
_ = require 'underscore'

Config = require '../config'
Term = require '../term'
Persist = require '../persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	ReactDOM = win.ReactDOM
	CrashHandler = require('../crashHandler').load(win)

	{
		FaIcon, renderLineBreaks, showWhen, capitalize
	} = require('../utils').load(win)


	InfoView = React.createFactory React.createClass
		displayName: 'InfoView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			detailUnitsById = @_getDetailUnitsById()

			return {
				firstName: @props.clientFile.getIn(['clientName', 'first'])
				middleName: @props.clientFile.getIn(['clientName', 'middle'])
				lastName: @props.clientFile.getIn(['clientName', 'last'])
				recordId: @props.clientFile.get('recordId')
				status: @props.clientFile.get('status')
				detailUnitsById
			}

		render: ->
			return R.div({className: "infoView"},

				hasChanges = @hasChanges()

				R.div({className: "flexButtonToolbar"},
					R.button({
						className:
							if hasChanges
								'saveButton'
							else
								'disabled'

						onClick: @_submit
					},
						FaIcon('save')
						' '
						"Save Changes"
					)
					R.button({
						className:
							if hasChanges
								'discardButton'
							else
								'disabled'

						onClick: @_resetChanges
					},
						FaIcon('undo')
						"Discard"
					)
				)

				R.div({className: 'basicInfo'},
					R.h4({}, "Client Name"),
					R.div({className: 'basicFields'}
						R.div({className: 'form-group'},
							R.label({}, "First name"),
							R.input({
								ref: 'firstNameField'
								className: 'form-control'
								onChange: @_updateFirstName
								value: @state.firstName
								# onKeyDown: @_onEnterKeyDown
								maxLength: 35
							})
						)
						R.div({className: 'form-group'},
							R.label({}, "Middle name"),
							R.input({
								className: 'form-control'
								onChange: @_updateMiddleName
								value: @state.middleName
								placeholder: "(optional)"
								maxLength: 35
							})
						)
						R.div({className: 'form-group'},
							R.label({}, "Last name"),
							R.input({
								className: 'form-control'
								onChange: @_updateLastName
								value: @state.lastName
								maxLength: 35
							})
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
									maxLength: 23
								})
							)
						)

						R.div({className: 'form-group'},
							R.label({}, "Client File Status"),
							R.div({className: 'btn-toolbar'},
								R.button({
									className:
										if @state.status is 'active'
											'btn btn-success'
										else 'btn btn-default'
									onClick: @_updateStatus
									value: 'active'

								},
									"Active"
								)
								R.button({
									className:
										if @state.status is 'inactive'
											'btn btn-warning'
										else 'btn btn-default'
									onClick: @_updateStatus
									value: 'inactive'

								},
									"Inactive"
								)
								R.button({
									className:
										if @state.status is 'discharged'
											'btn btn-danger'
										else 'btn btn-default'
									onClick: @_updateStatus
									value: 'discharged'

								},
									"Discharged"
								)
							)
						)
					)

				)

				R.div({className: 'detailUnitGroups'},
					(@props.detailDefinitionGroups.map (definitionGroup) =>
						groupId = definitionGroup.get('id')
						fields = definitionGroup.get('fields')

						R.div({className: 'detailUnitGroup'},
							R.h4({}, definitionGroup.get('title'))

							R.div({className: 'detailFields'},
								(fields.map (field) =>
									fieldId = field.get('id')
									value = @state.detailUnitsById.getIn([fieldId, 'value'])
									inputType = field.get('inputType')

									R.div({className: 'form-group'},
										R.label({}, "#{field.get('name')}"),

										R[inputType]({
											className: 'form-control'
											placeholder: field.get('placeholder')
											value
											onChange: @_updateDetailUnit.bind null, fieldId
											# maxLength: 35
										})
									)
								)
							)
						)
					)
				)
			)


		hasChanges: ->
			# If there is a difference, then there have been changes
			detailUnitsById = @_getDetailUnitsById()

			detailUnitsHasChanges = Imm.is detailUnitsById, @state.detailUnitsById
			statusHasChanges = @props.clientFile.get('status') is @state.status
			firstNameHasChanges = @props.clientFile.getIn(['clientName', 'first']) is @state.firstName
			middleNameHasChanges = @props.clientFile.getIn(['clientName', 'middle']) is @state.middleName
			lastNameHasChanges = @props.clientFile.getIn(['clientName', 'last']) is @state.lastName
			recordIdHasChanges = @props.clientFile.get('recordId') is @state.recordId

			unless detailUnitsHasChanges and
			statusHasChanges and
			firstNameHasChanges and
			middleNameHasChanges and
			lastNameHasChanges and
			recordIdHasChanges
				return true
			return false


		_updateDetailUnit: (fieldId, event) ->
			detailUnitsById = @state.detailUnitsById.setIn [fieldId, 'value'], event.target.value
			@setState {detailUnitsById}

		_updateFirstName: (event) ->
			@setState {firstName: event.target.value}

		_updateMiddleName: (event) ->
			@setState {middleName: event.target.value}

		_updateLastName: (event) ->
			@setState {lastName: event.target.value}

		_updateRecordId: (event) ->
			@setState {recordId: event.target.value}

		_updateStatus: (event) ->
			@setState {status: event.target.value}

		_getDetailUnitsById: ->
			existingDetailUnits = @props.clientFile.get('detailUnits')
			detailUnitsById = @props.detailDefinitionGroups.flatMap (definitionGroup) =>
				definitionGroup.get('fields').map (field) =>
					fieldId = field.get('id')
					existingDetailUnit = existingDetailUnits.find((unit) ->
						unit.get('fieldId') is fieldId)

					if existingDetailUnit?
						value = existingDetailUnit.get('value')
					else
						value = ''

					return [field.get('id'), Imm.fromJS {
						fieldId
						groupId: definitionGroup.get('id')
						value
					}]
				.fromEntrySeq().toMap()
			.fromEntrySeq().toMap()
			return detailUnitsById

		_resetChanges: ->
			Bootbox.confirm "Discard all changes made to the #{Term 'Client File'}?", (ok) =>
				if ok
					@setState @getInitialState()

		_submit: ->
			updatedDetailUnits = @state.detailUnitsById.toArray().map (detailUnit) =>
				detailUnit.toJS()

			updatedClientFile = @props.clientFile
			.setIn(['clientName', 'first'], @state.firstName)
			.setIn(['clientName', 'middle'], @state.middleName)
			.setIn(['clientName', 'last'], @state.lastName)
			.set('recordId', @state.recordId)
			.set('status', @state.status)
			.set('detailUnits', updatedDetailUnits)

			global.ActiveSession.persist.clientFiles.createRevision updatedClientFile, (err, obj) =>
				@refs.dialog.setIsLoading(false) if @refs.dialog?
				if err
					if err instanceof Persist.IOError
						console.error err
						console.error err.stack
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

	return {InfoView}

module.exports = {load}

