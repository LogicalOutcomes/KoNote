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

	OpenDialogLink = require('./openDialogLink').load(win)
	{FaIcon, showWhen, executeIfFunction} = require('./utils').load(win)

	OrderableTable = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]

		getDefaultProps: ->
			return {
				columns: Imm.List()
				rowKey: ['id']
				onClickRow: ->
				rowClass: ->
				rowIsVisible: -> return true				
			}

		getInitialState: ->
			firstColumn = @props.columns[0].dataPath

			return {
				orderedData: Imm.List()
				sortByData: if @props.sortByData? then @props.sortByData else firstColumn
				isSortAsc: null
			}

		componentDidUpdate: (oldProps, oldState) ->
			@_updateParentData() unless Imm.is oldProps.tableData, @props.tableData				

		componentDidMount: ->
			@_updateParentData()

		_updateParentData: ->
			return unless @props.onSortChange?
			orderedData = @_reorderData(@props.tableData)
			@props.onSortChange(orderedData)

		_reorderData: (tableData) ->
			orderedData = tableData
			.sortBy (dataPoint) => 
				value = dataPoint.getIn(@state.sortByData)
				if typeof value is 'string' then value.toLowerCase() else value
			.filter (dataPoint) => @props.rowIsVisible(dataPoint)	

			if @state.isSortAsc
				orderedData = orderedData.reverse()

			return orderedData

		render: ->
			orderedData = @_reorderData(@props.tableData)

			if orderedData.size is 0
				return R.div({
					className: 'orderableTable noMatchesMessage'
				},
					@props.noMatchesMessage or "No data available"
				)
			
			return R.div({className: 'orderableTable'},
				R.div({className: 'tableHead'},
					R.div({className: 'tableRow'},
						(@props.columns.map (column) =>
							return if column.isDisabled
							R.div({
								className: 'tableCell'
								key: column.name
							},
								R.div({
									className: 'dataValue'
									onClick: @_sortByData.bind(null, column.dataPath) unless column.isNotOrderable
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
				R.div({className: 'tableBodyContainer'},
					R.div({
						className: 'tableBody'
					},
						(orderedData.map (dataPoint) =>
							R.div({
								className: [
									'tableRow'
									executeIfFunction @props.rowClass(dataPoint)
								].join ' '
								key: dataPoint.getIn(@props.rowKey)
								onClick: @props.onClickRow dataPoint
							},
								(@props.columns.map (column) =>
									return if column.isDisabled
									R.div({
										key: column.name
										className: [
											'tableCell'
											'hasButtons' if column.buttons?
											column.cellClass if column.cellClass?
										].join ' '									
									},
										hasDataValue = column.dataPath? and dataPoint.getIn(column.dataPath).toString().length > 0
										hasExtraDataValue = column.extraPath? and dataPoint.getIn(column.extraPath).toString().length > 0

										R.div({
											className: 'dataValue'
											style: column.valueStyle(dataPoint) if column.valueStyle?
										},
											(if hasDataValue

												if column.value?
													executeIfFunction column.value dataPoint
												else if not column.hideValue? and not column.hideValue
													[
														dataPoint.getIn(column.dataPath)
														if hasExtraDataValue
															", " + dataPoint.getIn(column.extraPath)
													]
												else
													null

											else if column.defaultValue?
												(column.defaultValue)
											else
												null
											)
										)

										(if column.buttons?
											R.div({className: 'btn-group'},
												column.buttons.map (button) =>
													if button.dialog?
														# Flatten props from orderableTable API for OpenDialogLink
														props = {}

														_.extend(props, button.data, {
															className: button.className
															dialog: button.dialog
															rowData: dataPoint
														})

														OpenDialogLink(props,
															FaIcon(button.icon) if button.icon
															' '
															(if button.dataPath?
																dataPoint.getIn(button.dataPath)
															else
																executeIfFunction button.text, dataPoint
															)
														)
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
			)

		_sortByData: (sortByData) ->
			# Flip ordering if same sorting as before
			if sortByData is @state.sortByData
				@setState {isSortAsc: not @state.isSortAsc}
			else
				@setState {sortByData}

	return OrderableTable


module.exports = {load}
