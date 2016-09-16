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
			return {
				firstName: @props.clientFile.getIn(['clientName', 'first'])
				middleName: @props.clientFile.getIn(['clientName', 'middle'])
				lastName: @props.clientFile.getIn(['clientName', 'last'])
				recordId: @props.clientFile.get('recordId')
				status: @props.clientFile.get('status')
			}

		# componentWillReceiveProps: (newProps) ->
				# 	cb()
				# (cb) =>
				# 	# Creating additional fields from config
				# 	Config.clientDetailDefinitionGroups.map (group) =>
				# 		console.log "from config ->> ", group

				# 		console.log "groupTitle", group.title
				# 		groupFields = []
				# 		group.fields.map (field) =>
				# 			fieldObj = {
				# 				id: Persist.generateId()
				# 				name: field.name
				# 				inputType: field.inputType
				# 				placeholder: field.placeholder
				# 			}
				# 			console.log "fieldObj that was built", fieldObj
				# 			groupFields.push fieldObj
				# 			console.log "groupFields array _>>", groupFields

				# 		clientDetailDefinitionGroupObj = Imm.fromJS {
				# 			title: group.title
				# 			status: 'default'
				# 			fields: groupFields
				# 		}
				# 		console.log "finished obj before persist - >>>", clientDetailDefinitionGroupObj
				# 	cb()

				# (cb) =>

				# 	objs.map (obj) =>
				# 		Persist.clientDetailDefinitionGroups.create clientDetailDefinitionGroupObj, (err, result) =>
				# 			if err
				# 				cb err
				# 				return
				# 			newGroup = result
				# 			console.log "newly created group ->>>", newGroup.toJS()
				# 	cb()

		render: ->
			return R.div({className: "infoView"},
				R.div({className: 'basicInfo'},
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
							# onKeyDown: @_onEnterKeyDown
							maxLength: 35
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
			)



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


	return {InfoView}

module.exports = {load}

