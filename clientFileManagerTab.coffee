# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Page overlay for managing client files

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
	Dialog = require('./dialog').load(win)
	OrderableTable = require('./orderableTable').load(win)
	OpenDialogButton = require('./openDialogButton').load(win)
	CreateClientFileDialog = require('./createClientFileDialog').load(win)
	Spinner = require('./spinner').load(win)
	{FaIcon, openWindow, renderName, showWhen} = require('./utils').load(win)

	ClientFileManagerTab = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		render: ->
			return R.div({id: 'clientFileManagerTab'},
				R.div({className: 'header'},
					R.h1({}, Term 'Client Files')
				)
				R.div({className: 'main'},
					OrderableTable({
						data: Imm.List @props.clientFileHeaders
						rowKey: ['id']
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
					OpenDialogButton({
						className: 'btn btn-lg btn-primary'
						text: "New #{Term 'Client File'} "
						icon: 'plus'
						dialog: CreateClientFileDialog
					})
				)
			)

		_sortBy: (sortByData) ->
			@setState {sortByData}	


	return ClientFileManagerTab

module.exports = {load}
