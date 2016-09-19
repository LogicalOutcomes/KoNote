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

	{
		FaIcon, renderLineBreaks, showWhen, capitalize
	} = require('../utils').load(win)

	InfoView = React.createFactory React.createClass
		displayName: 'InfoView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			detailUnits = @props.clientFile.get('detailUnits')
			console.log "detailUnits", detailUnits.toJS()

			obj = {
				firstName: @props.clientFile.getIn(['clientName', 'first'])
				middleName: @props.clientFile.getIn(['clientName', 'middle'])
				lastName: @props.clientFile.getIn(['clientName', 'last'])
				recordId: @props.clientFile.get('recordId')
				status: @props.clientFile.get('status')

			}

			fieldsById = @props.clientDetailGroupHeaders.map (clientDetailGroupHeader) =>
				clientDetailGroupId = clientDetailGroupHeader.get('id')
				clientDetailGroup = @props.clientDetailGroupsById.get(clientDetailGroupId)
				clientDetailGroupFields = clientDetailGroup.get('fields')

				clientDetailGroupFields.map (field) =>
					fieldId = field.get('id')

					if detailUnits.size is 0
						obj[fieldId] = 'testaroni'
					else
						detailUnits.map (unit) =>
							if unit.get('fieldId') is fieldId
								obj[fieldId] = unit.get('value')

			console.log "obj", obj

			return obj

		render: ->
			return R.div({className: "infoView"},

				R.div({className: 'btn-toolbar'},
					R.button({
						className: 'btn btn-primary'
						onClick: @_submit
						disabled: not @state.firstName or not @state.lastName
					}, "Save changes")
				)


				R.div({className: 'basicInfo'},
					R.h4({}, "BASIC INFO"),
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
					if Config.clientFileRecordId.isEnabled
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

				# looping through additional field groups and creating a group div for each

				(@props.clientDetailGroupHeaders.map (clientDetailGroupHeader) =>
					clientDetailGroupId = clientDetailGroupHeader.get('id')
					clientDetailGroup = @props.clientDetailGroupsById.get(clientDetailGroupId)
					# console.log "clientDetailGroup", clientDetailGroup.toJS()

					clientDetailGroupFields = clientDetailGroup.get('fields')
					# console.log "fields", clientDetailGroupFields.toJS()

					R.div({className: 'additionalGroup'},
						R.h4({}, "#{clientDetailGroup.get('title')}"),

						# looping through each field in the group and adding the field
						(clientDetailGroupFields.map (field) =>
							# console.log "field", field.toJS()
							R.div({className: 'form-group'},
								R.label({}, "#{field.get('name')}"),

								if field.get('inputType') is 'input'
									fieldId = field.get('id')
									console.log "@state.fieldId", @state.fieldId
									R.input({
										className: 'form-control'
										placeholder: field.get('placeholder')
										value: @state.fieldId
										onChange: @_updateAdditionalField.bind null, fieldId
										maxLength: 35
									})
								if field.get('inputType') is 'textarea'
									R.textarea({
										className: 'form-control'
										placeholder: field.get('placeholder')
										value: @state.fieldId
										onChange: @_updateAdditionalField
										maxLength: 35
									})
							)
						)
					)
				)
			)

		_updateAdditionalField: (fieldId, event) ->
			@setState {fieldId: event.target.value}

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

		_submit: ->

			updatedDetailUnits = @props.clientFile.get('detailUnits')
			@props.clientDetailGroupHeaders.map (clientDetailGroupHeader) =>
				clientDetailGroupId = clientDetailGroupHeader.get('id')
				clientDetailGroup = @props.clientDetailGroupsById.get(clientDetailGroupId)
				clientDetailGroupFields = clientDetailGroup.get('fields')
				clientDetailGroup = @props.clientDetailGroupsById.get(clientDetailGroupId)

				clientDetailGroupFields.map (field) =>
					fieldId = field.get('id')
					updatedDetailUnits.push Imm.fromJS {
						fieldId
						value: @state.fieldId
					}
				console.log "updatedDetailUnits", updatedDetailUnits


			updatedClientFile = @props.clientFile
			.setIn(['clientName', 'first'], @state.firstName)
			.setIn(['clientName', 'middle'], @state.middleName)
			.setIn(['clientName', 'last'], @state.lastName)
			.set('recordId', @state.recordId)
			.set('status', @state.status)
			.set('detailUnits', updatedDetailUnits)

			console.log "clientFile", @props.clientFile.toJS()

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

