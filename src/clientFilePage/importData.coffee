# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Button component to open PrintPreviewPage window with @props.dataSet

Fs = require 'fs'
Path = require 'path'
Assert = require 'assert'
Imm = require 'immutable'
Moment = require 'moment'
Async = require 'async'
_ = require 'underscore'

Config = require '../config'
Term = require '../term'
Persist = require '../persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	WithTooltip = require('../withTooltip').load(win)
	{FaIcon, openWindow, showWhen} = require('../utils').load(win)


	ImportData = React.createFactory React.createClass
		displayName: 'ImportData'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			# hidden input for opening backup zip
			R.input({
				ref: 'nwbrowse'
				className: 'hidden'
				type: 'file'
			})

			R.button({
				ref: 'importButton'
				className: 'importButton'
				onClick: @_import.bind null, {
					extension: 'csv'
					onImport: @_confirmImport
				}
			},
				FaIcon('upload')
			)

		_import: ({extension, onImport}) ->
			console.log "clicked"
			console.log "@refs.nwvrowse", @refs.nwbrowse
			# Configures hidden file inputs with custom attributes, and clicks it
			$nwbrowse = $(@refs.nwbrowse)
			$nwbrowse
			.off()
			.attr('accept', ".#{extension}")
			.on('change', (event) => onImport event.target.value)
			.click()

			console.log "nwbrowse". $nwbrowse

		_confirmImport: (importFile) ->
			Bootbox.confirm {
				title: "Importing"
				message: "Now importing data from CSV. Are you sure you want to continue?"
				callback: (confirmed) =>
					unless confirmed
						return
					# @setState {
					# 	isLoading: true
					# 	installProgress: {message: "Restoring data file. This may take some time..."}
					# }
					@_importData(importFile)
			}

		_importData: (importFile) ->
			console.log importFile

	return ImportData


module.exports = {load}
