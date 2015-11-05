# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# A dialog for allowing the user to create a new client file

Persist = require './persist'
Imm = require 'immutable'
Config = require './config'
Term = require './term'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	CrashHandler = require('./crashHandler').load(win)
	LayeredComponentMixin =require('./layeredComponentMixin').load(win)
	Dialog = require('./dialog').load(win)
	Spinner = require('./spinner').load(win)
	{FaIcon, openWindow, renderName, showWhen} = require('./utils').load(win)

	ClientFileManagerTab = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		componentDidMount: ->
			# @refs.firstNameField.getDOMNode().focus()
		
		getInitialState: ->
			return {
				sortByData: ['clientName', 'last']
				isSortAsc: null
			}

		render: ->
			return R.div({id: 'clientFileManagerTab'},
				R.div({className: 'header'},
					R.h1({}, Term 'Client Files')
				)
				R.div({className: 'main'},
					OrderableTable({
						data: @props.clientFileHeaders
						columns: Imm.List [
							{
								name: "Last Name"
								dataPath: ['clientName', 'last']
								isDefault: true
							}
							{
								name: "Given Name(s)"
								dataPath: ['clientName', 'first']
								extraPath: ['clientName', 'middle']
							}
							# {
							# 	name: "Program"
							# 	dataPath: ['clientName', 'last']
							# }
							{
								name: Config.clientFileRecordId.label
								dataPath: ['recordId']
							}
						]
					})
				)
				R.div({className: 'optionsMenu'},
					OptionButton({
						className: 'btn btn-lg btn-primary'
						text: "New #{Term 'Client File'} "
						icon: 'plus'
						dialog: CreateClientFileDialog
					})
				)		
			)

		_sortBy: (sortByData) ->
			@setState {sortByData}

	OrderableTable = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				sortByData: @props.columns.first().dataPath
				isSortAsc: null
			}

		render: ->
			console.log "sortByData", @state.sortByData

			data = @props.data
			.sortBy (dataPoint) => dataPoint.getIn @state.sortByData

			if @state.isSortAsc
				data = data.reverse()

			return R.table({className: 'table table-striped'},
				R.thead({},
					R.tr({},
						(@props.columns.map ({name, dataPath}) =>
							R.th({
								onClick: @_sortBy.bind null, dataPath
							}, 
								name
								if @state.sortByData is dataPath
									" " + FaIcon("chevron-#{
										if @state.isSortAsc then 'up' else 'down'
									}")
							)
						)
					)
				)
				R.tbody({},
					(data.map (dataPoint) =>
						R.tr({key: dataPoint.get('id')},
							(@props.columns.map ({name, dataPath, extraPath}) =>
								R.td({},
									dataPoint.getIn(dataPath) if dataPath?
									# if extraPath?
									# 	", " + dataPoint.getIn(extraPath)
								)
							)
						)
					)
				)
			)

		_sortBy: (sortByData) ->
			# Flip ordering if same sorting as before
			if sortByData is @state.sortByData
				@setState {isSortAsc: not @state.isSortAsc}
			else
				@setState {
					sortByData
					isSortAsc: false
				}


	OptionButton = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin, LayeredComponentMixin]

		getInitialState: ->
			return {
				isOpen: false
			}

		render: ->
			return R.button({
				className: @props.className
				onClick: @_openDialog
			},
				@props.text
				FaIcon(@props.icon)
			)

		_openDialog: ->
			@setState {isOpen: true}

		renderLayer: ->
			unless @state.isOpen
				return R.div()

			return @props.dialog({
				onClose: =>
					@setState {isOpen: false}
				onCancel: =>
					@setState {isOpen: false}
				onSuccess: (clientFileId) =>
					@setState {isOpen: false}
			})
			

	CreateClientFileDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		componentDidMount: ->
			@refs.firstNameField.getDOMNode().focus()
		
		getInitialState: ->
			return {
				firstName: ''
				middleName: ''
				lastName: ''
				recordId: ''
				isOpen: true
			}
		render: ->
			Dialog({
				title: "Create New #{Term 'Client File'}"
				onClose: @props.onClose
			},
				R.div({className: 'createClientFileDialog'},
					R.div({className: 'form-group'},
						R.label({}, "First name"),
						R.input({
							ref: 'firstNameField'
							className: 'form-control'
							onChange: @_updateFirstName
							value: @state.firstName
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Middle name"),
						R.input({
							className: 'form-control'
							onChange: @_updateMiddleName
							value: @state.middleName
							placeholder: "(optional)"
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Last name"),
						R.input({
							className: 'form-control'
							onChange: @_updateLastName
							value: @state.lastName
						})
					)
					if Config.clientFileRecordId.isEnabled
						R.div({className: 'form-group'},
							R.label({}, Config.clientFileRecordId.label),
							R.input({
								className: 'form-control'
								onChange: @_updateRecordId
								value: @state.recordNumber
								placeholder: "(optional)"
							})
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
						}, "Create #{Term 'File'}")
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
		_submit: ->
			first = @state.firstName
			middle = @state.middleName
			last = @state.lastName
			recordId = @state.recordId

			@setState {isLoading: true}

			clientFile = Imm.fromJS {
			  clientName: {first, middle, last}
			  recordId: recordId
			  plan: {
			    sections: []
			  }
			}

			global.ActiveSession.persist.clientFiles.create clientFile, (err, obj) =>
				@setState {isLoading: false}

				if err
					if err instanceof Persist.IOError
						Bootbox.alert """
							Please check your network connection and try again.
						"""
						return

					CrashHandler.handle err
					return

				@props.onSuccess(obj.get('id'))


	return ClientFileManagerTab

module.exports = {load}
