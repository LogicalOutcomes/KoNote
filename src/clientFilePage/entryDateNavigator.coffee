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
			isLoading: false
		}

		componentDidMount: ->
			@_initDateTimePicker()

		componentWillUnmount: ->
			@datetimepicker.destroy()

		componentWillReceiveProps: (nextProps) ->
			{historyEntries} = nextProps

			# Update enabledDates when historyEntries has changed
			unless Imm.is historyEntries, @props.historyEntries
				dates = @_generateEnabledDates(nextProps.historyEntries).toJS()
				console.log "dates", dates
				@datetimepicker.enabledDates dates

		_generateEnabledDates: (historyEntries) ->
			# TODO: Disable selection of any month within min->max whose days are all disabled
			return historyEntries.map (e) -> makeMoment(e.get 'timestamp').startOf 'day'

		_initDateTimePicker: ->
			enabledDates = @_generateEnabledDates @props.historyEntries

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

			$input = $(@refs.hiddenInput)
			$input.datetimepicker({
				format: 'YYYY-MM-DD'
				enabledDates: enabledDates.toJS()
				useCurrent: false
				minDate
				maxDate
				widgetPositioning: {
					vertical: 'bottom'
				}
				widgetParent: '#entryDateNavigator'
				viewMode: 'years'
			}).on 'dp.change', ({date}) =>
				console.log "Called change!"
				@_skipToEntryDate(date)

			@datetimepicker = $input.data('DateTimePicker')

		_skipToEntryDate: (date) ->
			selectedMoment = Moment(date)

			# TODO: Have moment objs already pre-built
			entry = @props.historyEntries.find (e) ->
				timestampMoment = makeMoment e.get('timestamp')
				return selectedMoment.isSame timestampMoment, 'day'

			if not entry?
				throw new Error "Could not find day of #{selectedMoment.toDate()} in historyEntries"

			# Wrap the scroll process with isLoading
			@setState {isLoading: true}, => @props.onSelect entry, => @setState {isLoading: false}

		_toggleDateTimePicker: ->
			@datetimepicker.toggle()

		render: ->
			R.div({id: 'entryDateNavigator'},
				R.button({
					onClick: @_toggleDateTimePicker
					className: 'btn btn-default btn-xs'
				},
					"Find Date"
					FaIcon if @state.isLoading then 'refresh fa-spin fa-fw' else 'search'
				)
				R.input({ref: 'hiddenInput'})
			)


	return EntryDateNavigator

module.exports = {load}