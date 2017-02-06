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
			historyEntries: PropTypes.instanceOf(Imm.List)
			onSelect: PropTypes.func.isRequired
		}

		getDefaultProps: -> {
			historyEntries: Imm.List()
			onSelect: ->
		}

		getInitialState: -> {
			isScrolling: false
		}

		componentWillUnmount: ->
			@datetimepicker.destroy() if @datetimepicker?

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

			# Block phantom 'onChange' from firing during init
			@_tempDisableChangeEvent()

			$input = $(@refs.hiddenInput)

			$input.datetimepicker({
				debug: true
				format: 'YYYY-MM-DD'
				enabledDates: enabledDates.toJS()
				useCurrent: false
				minDate
				maxDate
				widgetPositioning: {
					horizontal: 'left'
					vertical: 'top'
				}
				widgetParent: '#navigatorWrapper'
				viewMode: 'years'
			})
			.on 'dp.change', ({date}) =>
				# Prevent invalid/duplicate calls of @_skipToEntryDate
				return if not date or @disableChange

				# TODO: Detect month (< >) changes to follow with scroll
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
			@setState {isScrolling: true}, => @props.onSelect entry, =>
				@setState {isScrolling: false}
				@refs.button.blur() if @refs.button

				# Highlight destination entries when scroll has completed
				entryIdsToFlash = @props.historyEntries
				.filter (e) ->
					timestampMoment = makeMoment e.get('timestamp')
					return selectedMoment.isSame timestampMoment, 'day'
				.map (e) ->
					return '#' + e.get('id')
				.toArray()
				.join ', '

				$(entryIdsToFlash).addClass 'flashDestination'

				setTimeout ->
					$(entryIdsToFlash).removeClass 'flashDestination'
				, 2500

		_tempDisableChangeEvent: ->
			# Temporarily disable datetimepicker's 'change' event from firing
			# This overrides default behaviour causing more events than needed
			@disableChange = true
			setTimeout (=> @disableChange = false), 500

		_handleClick: ->
			# Save on window.load perf by only mounting datetimepicker when used
			@_initDateTimePicker() unless @datetimepicker?
			@_tempDisableChangeEvent()
			@datetimepicker.toggle()

		_handleBlur: ->
			@datetimepicker.hide() if @datetimepicker?

		render: ->
			{isScrolling} = @state
			icon = if isScrolling then 'refresh fa-spin fa-fw' else 'sort'

			R.div({id: 'entryDateNavigator'},
				R.div({id: 'navigatorWrapper'},
					R.input({ref: 'hiddenInput'})

					R.button({
						ref: 'button'
						onClick: @_handleClick unless isScrolling
						onBlur: @_handleBlur
						className: [
							'btn btn-default btn-xs'
							'isScrolling' if isScrolling
						].join ' '
					},
						FaIcon(icon)
					)
				)
			)


	return EntryDateNavigator

module.exports = {load}