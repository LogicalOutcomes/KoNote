# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Table component with toggleable ordering

Imm = require 'immutable'
_ = require 'underscore'
Config = require './config'
Term = require './term'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	OpenDialogButton = require('./openDialogButton').load(win)
	{FaIcon, showWhen, executeIfFunction} = require('./utils').load(win)

	OrderableTable = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getDefaultProps: ->
			return {
				data: Imm.List()
				columns: Imm.List()
				rowKey: ['id']
				rowIsVisible: -> return true
			}

		getInitialState: ->
			firstColumn = @props.columns[0].dataPath

			return {
				sortByData: if @props.sortByData? then @props.sortByData else firstColumn
				isSortAsc: null
			}

		render: ->
			data = @props.tableData
			.sortBy (dataPoint) => 
				value = dataPoint.getIn(@state.sortByData)
				if typeof value is 'string' then value.toLowerCase() else value
			.filter (dataPoint) => @props.rowIsVisible(dataPoint)

			if @state.isSortAsc
				data = data.reverse()

			return R.table({className: 'table table-striped table-hover orderableTable'},
				R.thead({},
					R.tr({},
						(@props.columns.map (column) =>
							R.th({}, 
								R.span({
									onClick: @_sortByData.bind null, column.dataPath
								}, 
									column.name unless column.nameIsVisible? and not column.nameIsVisible

									if column.dataPath? and _.isEqual(@state.sortByData, column.dataPath)
										(FaIcon("chevron-#{
											if @state.isSortAsc then 'up' else 'down'
										}"))
								)
							)
						)
					)
				)
				R.tbody({},
					(data.map (dataPoint) =>
						R.tr({key: dataPoint.getIn(@props.rowKey)},
							(@props.columns.map (column) =>
								R.td({
									key: column.name
									className: [
										'hasButtons' if column.buttons?
										column.cellClass if column.cellClass?
									].join ' '									
								},
									hasDataValue = column.dataPath? and dataPoint.getIn(column.dataPath).toString().length > 0
									hasExtraDataValue = column.extraPath? and dataPoint.getIn(column.extraPath).toString().length > 0

									R.span({
										className: [
											'dataValue'
											'noValue' if not hasDataValue
										].join ' '
										style: column.valueStyle(dataPoint) if column.valueStyle?
									},
										(if hasDataValue
											if column.value?
												executeIfFunction column.value dataPoint
											else if not column.hideValue? and not column.hideValue
												dataPoint.getIn(column.dataPath)
										else if column.defaultValue?
											(column.defaultValue)										
										)
									)
									(if hasExtraDataValue
										R.span({className: 'extraDataValue'},
											", " + dataPoint.getIn(column.extraPath)
										)
									)

									(if column.buttons?
										R.div({className: 'btn-group'},
											column.buttons.map (button) =>
												if button.dialog?
													# Flatten props from orderableTable API for OpenDialogButton
													props = {}

													_.extend(props, button.data, {
														className: button.className
														text: if button.dataPath?
															dataPoint.getIn(button.dataPath)
														else
															executeIfFunction button.text, dataPoint
															
														icon: button.icon
														dialog: button.dialog
														rowData: dataPoint
													})

													OpenDialogButton(props)
												else
													R.button({
														className: button.className
														onClick: button.onClick(dataPoint)
													}, 
														button.text if button.text?
														FaIcon(button.icon) if button.icon?
													)
										)
									)
								)
							)
						)
					)
				)
			)

		_sortByData: (sortByData) ->
			# Flip ordering if same sorting as before
			if sortByData is @state.sortByData
				@setState {isSortAsc: not @state.isSortAsc}
			else
				@setState {
					sortByData
				}

	return OrderableTable


module.exports = {load}