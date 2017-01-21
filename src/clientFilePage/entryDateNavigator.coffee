# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Button that pops up a calendar, allowing the user to select a specific date
# The enabled/selectable dates are populated by @props.historyEntries
# Scrolling functionality is handled internally by EntriesListView

Imm = require 'immutable'
Moment = require 'moment'

{TimestampFormat} = require '../persist'


load = (win) ->
	$ = win.jQuery
	React = win.React
	{PropTypes} = React
	R = React.DOM

	{FaIcon, makeMoment} = require('../utils').load(win)


	EntryDateNavigator = React.createFactory React.createClass
		displayName: 'EntryDateNavigator'

		propTypes: {
			historyEntries: PropTypes.instanceOf Imm.List()
			onSelect: PropTypes.func.isRequired
		}

		getDefaultProps: -> {
			historyEntries: Imm.List()
			onSelect: ->
		}

		getInitialState: -> {
			isScrolling: false
		}

		componentDidMount: ->
			@_initDateTimePicker()

		componentWillUnmount: ->
			@datetimepicker.destroy()

		componentDidUpdate: (oldProps, oldState) ->
			# Re-init enabledDates when historyEntries has changed
			# TODO: Use enabledDates API funct (currently doesn't work)
			unless Imm.is oldProps.historyEntries, @props.historyEntries
				console.log "Refreshing entryDateNavigator"
				@_initDateTimePicker()

		_generateEnabledDates: (historyEntries) ->
			# TODO: Disable selection of any month within min->max whose days are all disabled
			return historyEntries.map (e) -> makeMoment(e.get 'timestamp').startOf 'day'

		_initDateTimePicker: (props) ->
			# Destroy any pre-existing instance
			@datetimepicker.destroy() if @datetimepicker?

			if @props.historyEntries.isEmpty()
				console.warn "Cancelled datetimepicker init, historyEntries is empty"
				return

			enabledDates = @props.historyEntries.map (e) -> makeMoment(e.get 'timestamp').startOf 'day'

			#	historyEntries are in reverse-order
			minDate = enabledDates.last()
			maxDate = enabledDates.first()

			# Show the largest viewMode required to start selecting
			viewMode = if minDate.isSame(maxDate, 'month')
				'days'
			else if minDate.isSame(maxDate, 'year')
				'months'
			else
				'years'

			@disableChange = true
			setTimeout(=>
				@disableChange = false
			, 150)

			$input = $(@refs.hiddenInput)

			$input.datetimepicker({
				format: 'YYYY-MM-DD'
				enabledDates: enabledDates.toJS()
				useCurrent: false
				minDate
				maxDate
				widgetPositioning: {
					horizontal: 'right'
				}
				widgetParent: '#navigatorWrapper'
				viewMode: 'years'
			})
			.on 'dp.change', ({date}) =>
				# Prevent invalid/duplicate calls of @_skipToEntryDate
				return if not date or @disableChange or (date.isSame? and date.isSame @lastDate)
				@lastDate = date

				# TODO: use 'dp.update' to scroll top of month selection
				@_skipToEntryDate(date)


			@datetimepicker = $input.data('DateTimePicker')

		_skipToEntryDate: (date) ->
			selectedMoment = Moment(+date)

			# TODO: Have moment objs already pre-built
			entry = @props.historyEntries.find (e) ->
				timestampMoment = makeMoment e.get('timestamp')
				return selectedMoment.isSame timestampMoment, 'day'

			if not entry?
				console.warn "Cancelled scroll, could not find #{selectedMoment.toDate()} in historyEntries"
				return

			# Update the icon with an animated spinner while isScrolling
			@setState {isScrolling: true}, => @props.onSelect entry, => @setState {isScrolling: false}

		_toggleDateTimePicker: ->
			@datetimepicker.toggle()

		render: ->
			icon = if @state.isScrolling then 'refresh fa-spin fa-fw' else 'sort'

			R.div({id: 'entryDateNavigator'},
				R.div({id: 'navigatorWrapper'},
					R.input({ref: 'hiddenInput'})

					R.button({
						onClick: @_toggleDateTimePicker
						className: 'btn btn-default btn-xs animated fadeInRight'
					},
						FaIcon(icon)
					)
				)
			)


	return EntryDateNavigator

module.exports = {load}