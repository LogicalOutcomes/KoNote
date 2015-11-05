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
	OrderableTable = require('./orderableTable').load(win)
	CreateClientFileDialog = require('./createClientFileDialog').load(win)
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
								defaultValue: "n/a"
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
				onSuccess: =>
					@setState {isOpen: false}
			})


	return ClientFileManagerTab

module.exports = {load}
