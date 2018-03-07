# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Dropdown menu selectors component for birth dates, as: month, day, year

Moment = require 'moment'


load = (win) ->
	React = win.React
	R = React.DOM

	B = require('./utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	months = Moment.monthsShort()
	currentYear = Moment().year()
	earlyYear = currentYear - 100


	BirthDateSelector = React.createFactory React.createClass
		displayName: 'BirthDateSelector'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		render: ->
			{birthDay, birthMonth, birthYear, onSelectMonth, onSelectDay, onSelectYear} = @props


			R.div({className: 'birthDateSelector'},

				R.div({className: 'btn-group btn-group-dropdowns'},
					B.DropdownButton({
						id: 'birthMonthDropdown'
						title: if birthMonth? then birthMonth else "Month"
						disabled: @props.disabled
					},
						(months.map (month) =>
							B.MenuItem({
								key: month
								onClick: onSelectMonth.bind null, month
							},
								month
							)
						)
					)
					B.DropdownButton({
						id: 'birthDayDropdown'
						title: if birthDay? then birthDay else "Day"
						disabled: @props.disabled
					},
						# TODO: Derive list of days from selected month
						(for day in [1..31]
							B.MenuItem({
								key: day
								onClick: onSelectDay.bind null, day
							},
								day
							)
						)
					)

					B.DropdownButton({
						id: 'birthYearDropdown'
						title: if birthYear? then birthYear else "Year"
						disabled: @props.disabled
					},
						(for year in [currentYear..earlyYear]
							B.MenuItem({
								key: year
								onClick: onSelectYear.bind null, year
							},
								year
							)
						)
					)
				)
			)
	return BirthDateSelector

module.exports = {load}
