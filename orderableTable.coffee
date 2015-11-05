# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Table component with toggleable ordering

Imm = require 'immutable'
Config = require './config'
Term = require './term'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	{FaIcon, showWhen} = require('./utils').load(win)

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
			.sortBy (dataPoint) => dataPoint.getIn(@state.sortByData).toLowerCase()

			if @state.isSortAsc
				data = data.reverse()

			return R.table({className: 'table table-striped orderableTable'},
				R.thead({},
					R.tr({},
						(@props.columns.map ({name, dataPath}) =>
							R.th({}, 
								R.span({
									onClick: @_sortBy.bind null, dataPath
								}, 
									name
									if @state.sortByData is dataPath
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
						R.tr({key: dataPoint.get('id')},
							(@props.columns.map ({name, dataPath, extraPath, defaultValue}) =>
								R.td({},
									
									hasDataValue = dataPath? and dataPoint.getIn(dataPath).length > 0
									hasExtraDataValue = extraPath? and dataPoint.getIn(extraPath).length > 0

									R.span({className: "dataValue #{'noValue' if not hasDataValue}"},
										(if hasDataValue
											dataPoint.getIn(dataPath)
										else if defaultValue?
											(defaultValue)
										)
									)
									(if hasExtraDataValue
										R.span({className: 'extraDataValue'},
											", " + dataPoint.getIn(extraPath)
										)
									)
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

	return OrderableTable


module.exports = {load}