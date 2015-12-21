# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'	
Imm = require 'immutable'
_ = require 'underscore'

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
	Spinner = require('./spinner').load(win)
	OrderableTable = require('./orderableTable').load(win)
	OpenDialogLink = require('./openDialogLink').load(win)
	ExpandingTextArea = require('./expandingTextArea').load(win)
	{FaIcon, showWhen, stripMetadata, renderName} = require('./utils').load(win)

	EventTypeManagerTab = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		render: ->

			return R.div({className: 'programManagerTab'},
				R.div({className: 'header'},
					R.h1({}, Term 'Event Types')
				)
				R.div({className: 'main'},
					OrderableTable({
						tableData: @props.eventTypes
						sortByData: ['name']
						columns: [
							{
								name: "Color Key"
								nameIsVisible: false
								dataPath: ['colorKeyHex']								
								cellClass: 'colorKeyCell'
								valueStyle: (dataPoint) ->
									return {
										background: dataPoint.get('colorKeyHex')
									}
								hideValue: true
							}
							{
								name: "Type Name"
								dataPath: ['name']
								cellClass: 'nameCell'
							}
							{
								name: "Description"
								dataPath: ['description']
							}
							{
								name: "Options"
								nameIsVisible: false
								cellClass: 'optionsCell'
								# buttons: [
								# 	{
								# 		className: 'btn btn-warning'
								# 		text: null
								# 		icon: 'wrench'
								# 		dialog: ModifyProgramDialog
								# 		data: 
								# 			clientFileProgramLinks: @props.clientFileProgramLinks
								# 	}
								# ]
							}
						]
					})
				)
				R.div({className: 'optionsMenu'},
					OpenDialogLink({
						className: 'btn btn-lg btn-primary'
						dialog: CreateEventTypeDialog
					},
						FaIcon('plus')
						' '
						"New #{Term 'Event Type'} "
					)
				)
			)	

	CreateEventTypeDialog = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				name: ''
				colorKeyHex: null
				description: ''
			}

		componentDidMount: ->
			@refs.name.focus()
			@_initColorPicker @refs.colorPicker

		render: ->
			return Dialog({
				title: "Create New #{Term 'Event Type'}"
				onClose: @props.onCancel
			},
				R.div({className: 'createEventTypeDialog'},
					R.div({className: 'form-group'},						
						R.label({}, "Name and Color Key")
						R.div({className: 'input-group'},
							R.input({
								className: 'form-control'
								ref: 'name'
								value: @state.name
								onChange: @_updateName
								style:
									borderColor: @state.colorKeyHex
							})
							R.div({
								className: 'input-group-addon'
								id: 'colorPicker'
								ref: 'colorPicker'
								style:
									background: @state.colorKeyHex
									borderColor: @state.colorKeyHex
							},
								R.span({
									className: 'hasColor' if @state.colorKeyHex?
								},
									FaIcon 'eyedropper'
								)
							)
						)
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						R.textarea({
							className: 'form-control'
							value: @state.description
							onChange: @_updateDescription
							rows: 3
						})
					)					
					R.div({className: 'btn-toolbar'},
						R.button({
							className: 'btn btn-default'
							onClick: @props.onCancel
						}, "Cancel")
						R.button({
							className: 'btn btn-success'
							disabled: not @state.name or not @state.description or not @state.colorKeyHex
							onClick: @_createEventType
						}, 
							"Create #{Term 'Event Type'}"
						)
					)
				)
			)

		_initColorPicker: (colorPicker) ->
			# Set up color picker
			$(colorPicker).spectrum(
				showPalette: true
				palette: [
					['YellowGreen', 'Tan', 'Violet']
					['Teal', 'Sienna', 'RebeccaPurple']
					['Maroon', 'Cyan', 'LightSlateGray']
				]
				move: (color) =>
					colorKeyHex = color.toHexString()
					@setState {colorKeyHex}
			)

		_updateName: (event) ->
			@setState {name: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_createEventType: (event) ->
			event.preventDefault()

			newProgram = @_buildProgramObject()

			# Create the new program, and close
			ActiveSession.persist.programs.create newProgram, (err, newProgram) =>
				if err
					CrashHandler.handle err
					return

				@props.onSuccess()


	return EventTypeManagerTab

module.exports = {load}
