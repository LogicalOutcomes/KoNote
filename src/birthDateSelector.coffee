# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Moment = require 'moment'

load = (win) ->
	React = win.React
	R = React.DOM

	B = require('./utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')
	{FaIcon} = require('./utils').load(win)

	months = Moment.monthsShort()
	birthDateFormat = 'YYYYMMMDD'
	currentYear = Moment().year()
	earlyYear = currentYear - 100

	BirthDateSelector = React.createFactory React.createClass
		displayName: 'BirthDateSelector'
		mixins: [React.addons.PureRenderMixin]

		render: ->

			{birthDay, birthMonth, birthYear, onSelectMonth, onSelectDay, onSelectYear} = @props

			return R.div({},
				B.DropdownButton({
					id: 'birthMonthDropdown'
					title: if birthMonth? then birthMonth else "Month"
				},
					(months.map (month) =>
						B.MenuItem({
							key: month
							onClick: onSelectMonth.bind null, month
						},
							R.div({
								onclick: onSelectMonth.bind null, month
							},
								month
							)
						)
					)
				)
				B.DropdownButton({
					id: 'birthDayDropdown'
					title: if birthDay? then birthDay else "Day"
				},
					for day in [1..31]
						B.MenuItem({
							key: day
							onClick: onSelectDay.bind null, day
						},
							R.div({
								onClick: onSelectDay.bind null, day
							},
								day
							)
						)
				)

				B.DropdownButton({
					id: 'birthYearDropdown'
					title: if birthYear? then birthYear else "Year"
				},
					for year in [currentYear..earlyYear]
						B.MenuItem({
							key: year
							onClick: onSelectYear.bind null, year
						},
							R.div({
								onClick: onSelectYear.bind null, year
							},
								year
							)
						)
				)
			)
	return BirthDateSelector

module.exports = {load}