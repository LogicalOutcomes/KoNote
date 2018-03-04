# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# The Client Information tab on the client file page.

Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'
Term = require '../term'
Persist = require '../persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('../crashHandler').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	BirthDateSelector = require('../birthDateSelector').load(win)

	{FaIcon} = require('../utils').load(win)

	birthDateFormat = 'YYYYMMMDD'

	InfoView = React.createFactory React.createClass
		displayName: 'InfoView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			detailUnitsById = @_getDetailUnitsById()

			if @props.clientFile.get('birthDate') isnt ''
				birthMonth = Moment(@props.clientFile.get('birthDate'), birthDateFormat, true).format('MMM')
				birthDay = Moment(@props.clientFile.get('birthDate'), birthDateFormat, true).format('DD')
				birthYear = Moment(@props.clientFile.get('birthDate'), birthDateFormat, true).format('YYYY')
			else
				birthMonth = null
				birthDay = null
				birthYear = null

			return {
				firstName: @props.clientFile.getIn(['clientName', 'first'])
				middleName: @props.clientFile.getIn(['clientName', 'middle'])
				lastName: @props.clientFile.getIn(['clientName', 'last'])
				recordId: @props.clientFile.get('recordId')
				status: @props.clientFile.get('status')
				detailUnitsById
				selectedGroupId: null
				birthDay
				birthMonth
				birthYear
			}

		componentDidMount: ->
			if Moment(@props.clientFile.get('birthDate'), birthDateFormat, true).format('YYYYMMMDD') is "Invalid Date"
				Bootbox.alert "Warning! Invalid birthdate detected. Please update and save."

		render: ->
			hasChanges = @hasChanges()
			currentYear = Moment().year()

			return R.div({className: 'infoView'},

				R.div({
					className: [
						'menuBar'
						'hasChanges' if hasChanges
					].join ' '
				},
					R.div({className: 'title'},
						R.span({},
							"#{Term 'Client'} Information"
						)
					)
					R.div({className: 'flexButtonToolbar'},
						R.button({
							className: [
								'discardButton'
								'collapsed' unless hasChanges
							].join ' '
							onClick: @_resetChanges
							disabled: @props.isReadOnly
						},
							FaIcon('undo')
							' '
							"Discard"
						)
						R.button({
							className: [
								'saveButton'
								'collapsed' unless hasChanges
							].join ' '
							onClick: @_submit
							disabled: @props.isReadOnly
						},
							FaIcon('save')
							' '
							"Save Changes"
						)
					)
				)

				R.div({className: 'detailUnitsContainer'},

					R.div({
						id: 'basicInfoGroup'
						className: [
							'detailUnitGroup'
							'isSelected' if @_isSelected('basic')
						].join ' '
						onBlur: @_updateSelectedGroupId.bind null, null
					},
						(if Config.features.clientAvatar.isEnabled
							# TODO: Client photo/avatar feature
							R.section({className: 'avatar'},
								R.div({},
									FaIcon('user')
								)
							)
						)

						R.section({className: 'nameId'},
							R.table({},
								R.tbody({},
									R.tr({},
										R.td({}, "First Name")
										R.td({},
											R.input({
												ref: 'firstNameField'
												className: 'form-control'
												onChange: @_updateFirstName
												onClick: @_updateSelectedGroupId.bind null, 'basic'
												value: @state.firstName
												disabled: @props.isReadOnly
												maxLength: 35
											})
										)
									)
									R.tr({},
										R.td({}, "Middle Name")
										R.td({},
											R.input({
												className: 'form-control'
												onChange: @_updateMiddleName
												onClick: @_updateSelectedGroupId.bind null, 'basic'
												value: @state.middleName
												placeholder: "(optional)"
												disabled: @props.isReadOnly
												maxLength: 35
											})
										)
									)
									R.tr({},
										R.td({}, "Last Name")
										R.td({},
											R.input({
												className: 'form-control'
												onChange: @_updateLastName
												onClick: @_updateSelectedGroupId.bind null, 'basic'
												value: @state.lastName
												disabled: @props.isReadOnly
												maxLength: 35
											})
										)
									)
									R.tr({},
										R.td({}, "Birthdate")
										R.td({},
											BirthDateSelector({
												birthDay: @state.birthDay
												birthMonth: @state.birthMonth
												birthYear: @state.birthYear
												onSelectMonth: @_updateBirthMonth
												onSelectDay: @_updateBirthDay
												onSelectYear: @_updateBirthYear
												disabled: @props.isReadOnly
											})
										)
									)
									(if Config.clientFileRecordId.isEnabled
										R.tr({},
											R.td({}, Config.clientFileRecordId.label)
											R.td({},
												R.input({
													className: 'form-control'
													onChange: @_updateRecordId
													onClick: @_updateSelectedGroupId.bind null, 'basic'
													value: @state.recordId
													placeholder: "(optional)"
													disabled: @props.isReadOnly
													maxLength: 23
												})
											)
										)
									)
								)
							)
						)

						R.section({className: 'status'},
							R.h4({}, "#{Term 'File'} Status")
							R.div({className: 'btn-toolbar'},
								R.button({
									className:
										if @state.status is 'active'
											'btn btn-success'
										else 'btn btn-default'
									onClick: @_updateStatus
									disabled: @props.isReadOnly
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
									disabled: @props.isReadOnly
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
									disabled: @props.isReadOnly
									value: 'discharged'
								},
									"Discharged"
								)
							)
						)

					)

					R.div({className: 'detailUnitGroups'},
						(@props.detailDefinitionGroups.map (definitionGroup) =>
							groupId = definitionGroup.get('id')
							fields = definitionGroup.get('fields')

							isSelected = @_isSelected(groupId)

							R.div({
								key: groupId
								className: [
									'detailUnitGroup'
									'isSelected' if isSelected
								].join ' '
								onBlur: @_updateSelectedGroupId.bind null, null
							},
								R.h4({}, definitionGroup.get('title'))

								R.table({},
									R.tbody({},
										(fields.map (field) =>
											fieldId = field.get('id')
											value = @state.detailUnitsById.getIn([fieldId, 'value'])
											inputType = field.get('inputType')

											# Special case for textarea to use our ExpandingTextArea
											InputComponent = if inputType is 'textarea'
												ExpandingTextArea
											else
												R[inputType]

											R.tr({key: fieldId},
												R.td({}, field.get('name'))
												R.td({},
													InputComponent({
														className: 'form-control'
														placeholder: "( #{field.get('placeholder')} )"
														value
														onChange: @_updateDetailUnit.bind null, fieldId
														disabled: @props.isReadOnly
														onClick: @_updateSelectedGroupId.bind null, groupId
													})
												)
											)
										)
									)
								)
							)
						)
					)
				)
			)

		_isSelected: (groupId) ->
			return groupId is @state.selectedGroupId

		hasChanges: ->
			# If there is a difference, then there have been changes
			detailUnitsById = @_getDetailUnitsById()

			detailUnitsHasChanges = not Imm.is detailUnitsById, @state.detailUnitsById
			statusHasChanges = @props.clientFile.get('status') isnt @state.status
			firstNameHasChanges = @props.clientFile.getIn(['clientName', 'first']) isnt @state.firstName
			middleNameHasChanges = @props.clientFile.getIn(['clientName', 'middle']) isnt @state.middleName
			lastNameHasChanges = @props.clientFile.getIn(['clientName', 'last']) isnt @state.lastName
			recordIdHasChanges = @props.clientFile.get('recordId') isnt @state.recordId
			# if there was a valid date in props, check state and props. if date props is empty, check state and null
			if @props.clientFile.get('birthDate') isnt ''
				birthMonthHasChanges = Moment(@props.clientFile.get('birthDate'), birthDateFormat, true).format('MMM') isnt @state.birthMonth
				birthDayHasChanges = Moment(@props.clientFile.get('birthDate'), birthDateFormat, true).format('DD') isnt @state.birthDay
				birthYearHasChanges = Moment(@props.clientFile.get('birthDate'), birthDateFormat, true).format('YYYY') isnt @state.birthYear
			else
				birthMonthHasChanges = @state.birthMonth isnt null
				birthDayHasChanges = @state.birthDay isnt null
				birthYearHasChanges = @state.birthYear isnt null

			return detailUnitsHasChanges or
			statusHasChanges or
			firstNameHasChanges or
			middleNameHasChanges or
			lastNameHasChanges or
			recordIdHasChanges or
			birthYearHasChanges or
			birthDayHasChanges or
			birthMonthHasChanges

		_updateSelectedGroupId: (groupId, event) ->
			selectedGroupId = groupId
			@setState {selectedGroupId}

		_updateDetailUnit: (fieldId, event) ->
			detailUnitsById = @state.detailUnitsById.setIn [fieldId, 'value'], event.target.value
			@setState {detailUnitsById}

		_updateFirstName: (event) ->
			@setState {firstName: event.target.value}

		_updateMiddleName: (event) ->
			@setState {middleName: event.target.value}

		_updateLastName: (event) ->
			@setState {lastName: event.target.value}

		_updateBirthMonth: (birthMonth) ->
			birthMonth = Moment(birthMonth, 'MMM', true).format('MMM')
			@setState {birthMonth}

		_updateBirthDay: (birthDay) ->
			birthDay = Moment(birthDay, 'D', true).format('DD')
			@setState {birthDay}

		_updateBirthYear: (birthYear) ->
			birthYear = Moment(birthYear, 'YYYY', true).format('YYYY')
			@setState {birthYear}

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
			Bootbox.confirm "Discard all changes made to the #{Term 'client file'}?", (ok) =>
				if ok
					@setState @getInitialState()

		_submit: ->
			if not @state.firstName
				Bootbox.alert "Cannot save the #{Term 'client file'} without a first name"
				return

			else if not @state.lastName
				Bootbox.alert "Cannot save the #{Term 'client file'} without a last name"
				return

			else if (@state.birthDay? or @state.birthMonth? or @state.birthYear?) and not (@state.birthDay? and @state.birthMonth? and @state.birthYear?)
				Bootbox.alert "Cannot save the #{Term 'client file'} without a valid birthdate"
				return

			else
				updatedDetailUnits = @state.detailUnitsById.toArray().map (detailUnit) =>
					detailUnit.toJS()

				if @state.birthYear? and @state.birthMonth? and @state.birthDay?
					updatedBirthDate = Moment(@state.birthYear + @state.birthMonth + @state.birthDay, birthDateFormat, true).format(birthDateFormat)
				else
					updatedBirthDate = ''

				updatedClientFile = @props.clientFile
				.setIn(['clientName', 'first'], @state.firstName)
				.setIn(['clientName', 'middle'], @state.middleName)
				.setIn(['clientName', 'last'], @state.lastName)
				.set('recordId', @state.recordId)
				.set('status', @state.status)
				.set('detailUnits', updatedDetailUnits)
				.set('birthDate', updatedBirthDate)


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

