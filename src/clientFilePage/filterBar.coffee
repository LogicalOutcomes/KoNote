# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Toolbar for handling search query (via props and internal copy),
# and a dropdown menu handling selection for options within each filter type

_ = require 'underscore'
Imm = require 'immutable'
Moment = require 'moment'

Term = require '../term'


load = (win) ->
	React = win.React
	{PropTypes} = React
	{findDOMNode} = win.ReactDOM
	R = React.DOM
	$ = win.jQuery

	ColorKeyBubble = require('../colorKeyBubble').load(win)
	{FaIcon, showWhen, makeMoment} = require('../utils').load(win)


	FilterBar = React.createFactory React.createClass
		displayName: 'FilterBar'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			# TODO: isRequired?
			programIdFilter: PropTypes.string
			dataTypeFilter: PropTypes.oneOf ['progNotes', 'targets', 'events']
			programsById: PropTypes.instanceOf Imm.List()
			dataTypeOptions: PropTypes.instanceOf Imm.List()
			dateSpanFilter: PropTypes.instanceOf Imm.Map()

			onClose: PropTypes.func
			onUpdateSearchQuery: PropTypes.func
			onSelectProgramId: PropTypes.func
			onSelectDataType: PropTypes.func
			onSelectDateSpan: PropTypes.func
		}

		getInitialState: -> {
			searchText: '' # Stays internal for perf reasons
		}

		componentWillMount: ->
			# Sparingly update the parent progNotesTab UI
			@_updateSearchQuery = _.debounce(@props.onUpdateSearchQuery, 350)

		componentDidMount: ->
			@_focusInput()

		clear: ->
			@_updateSearchText {target: {value: ''}}
			@props.onSelectProgramId null
			@props.onSelectDataType null
			@_focusInput()

		_focusInput: ->
			@refs.searchText.focus() if @refs.searchText?

		_updateSearchText: (event) ->
			searchText = event.target.value

			@setState {searchText}
			@_updateSearchQuery(searchText)

		render: ->
			R.div({
				className: 'filterBar'
				onClick: @_focusInput
			},
				R.section({},
					R.input({
						ref: 'searchText'
						className: 'form-control'
						value: @state.searchText
						onChange: @_updateSearchText
						placeholder: "Search by keywords . . ."
					})
				)
				R.section({className: 'filters'},
					FilterDropdownMenu({
						title: 'Data'
						selectedValue: @props.dataTypeFilter
						dataOptions: @props.dataTypeOptions
						onSelect: @props.onSelectDataType
					})

					(unless @props.programsById.isEmpty()
						FilterDropdownMenu({
							title: Term 'Programs'
							selectedValue: @props.programIdFilter
							dataOptions: @props.programsById
							onSelect: @props.onSelectProgramId
						})
					)

					FilterDropdownMenu({
						title: "Dates"
						dataOptions: Imm.List()
						selectedValue: @props.dateSpanFilter
						onSelect: @props.onSelectDateSpan
						selectedDisplay: =>
							{startDate, endDate} = @props.dateSpanFilter.toObject()

							if startDate and endDate
								if startDate.isBefore(endDate)
									"#{@props.dateSpanFilter.get('startDate').format('D MMM')} - #{@props.dateSpanFilter.get('endDate').format('D MMM')}"
								else
									"(invalid range)"
							else
								"(invalid)"
					},
						DateSpanSelection({
							dateSpanFilter: @props.dateSpanFilter
							historyEntries: @props.historyEntries
							onSelect: @props.onSelectDateSpan
						})
					)
				)
				R.section({
					className: 'closeButton'
					onClick: @props.onClose
				},
					FaIcon('times-circle')
				)
			)


	FilterDropdownMenu = React.createFactory React.createClass
		displayName: 'FilterDropdownMenu'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {
			isOpen: false
		}

		componentDidMount: ->
			win.document.addEventListener 'click', @_onDocumentClick

		componentWillUnmount: ->
			win.document.removeEventListener 'click', @_onDocumentClick

		_onDocumentClick: (event) ->
			console.log "------------------------"
			# return if event.className is 'dateSpanPicker'
			console.log "There was a click for #{@props.title}!"
			button = findDOMNode @refs.menuButton
			optionsList = findDOMNode @refs.optionsList

			# Check for inside/outside click
			if button.contains event.target
				console.log "toggle open!"
				@_toggleIsOpen()
			else if not optionsList.contains(event.target)
				unless @state.isOpen
					console.log "never mind, already closed"
					return

				console.log "close it"
				@setState {isOpen: false}
			else
				console.log "Unknown, do nothing"
				return

		_onSelectOption: (optionId) ->
			@setState {isOpen: false}
			@props.onSelect(optionId)

		_toggleIsOpen: ->
			@setState {isOpen: not @state.isOpen}

		render: ->
			console.log "dropdown render"
			{title, dataOptions, selectedValue, selectedDisplay, onSelect} = @props
			hasSelection = !!selectedValue

			if dataOptions and hasSelection
				# Filter out selected option from the list
				selectedOption = dataOptions.find (o) -> o.get('id') is selectedValue
				dataOptions = dataOptions.remove(selectedOption)

			R.div({
				className: [
					'filterDropdownMenu'
					'isOpen' if @state.isOpen
				].join ' '
			},
				# Hidden <ul> of dataOptions
				R.ul({
					ref: 'optionsList'
					className: 'filterOptions'
				},
					(if hasSelection
						R.li({
							className: 'option selectAllOption'
							onClick: onSelect.bind null, null
						},
							R.span({className: 'value'},
								"All #{title}"
							)
						)
					)

					# Use custom children if defined, otherwise iterate over dataOptions
					@props.children or (
						dataOptions.map (option) =>
							FilterOption({
								option
								onSelect: @_onSelectOption
							})
					)
				)

				# Visible option either shows
				R.div({
					ref: 'menuButton'
					className: 'option selectedValue'
				},
					(if selectedDisplay and hasSelection # Custom display for datespan
						selectedDisplay()
					else if hasSelection # Use selected option
						FilterOption({
							option: selectedOption
							onSelect
						})
					else # Default to "All X"
						R.span({className: 'value'},
							"All #{title}"
						)
					)
					' '
					FaIcon('caret-down')
				)
			)


	FilterOption = ({option, onSelect}) ->
		{id, name, colorKeyHex} = option.toObject()

		return R.li({
			key: id
			className: 'option'
			onClick: onSelect.bind null, id
		},
			(if colorKeyHex?
				ColorKeyBubble {
					key: 'bubble'
					colorKeyHex: colorKeyHex
					# Use a checkmark icon if this is the current user's program
					icon: 'check' if id is global.ActiveSession.programId
				}
			)
			R.span({
				key: 'value'
				className: 'value'
			},
				name
			)
		)


	DateSpanSelection = ({dateSpanFilter, historyEntries, onSelect}) ->
		startDate = if dateSpanFilter then dateSpanFilter.get('startDate')
		endDate = if dateSpanFilter then dateSpanFilter.get('endDate')

		[
			R.li({key: 'startDate', className: '', onClick: => @startDate.toggle()},
				"From "
				FaIcon('calendar-o')

				DateSpanPicker({
					ref: (node) => @startDate = node
					type: 'startDate'
					date: startDate
					historyEntries
					onSelect
				})
			)

			R.li({key: 'endDate', className: '', onClick: => @endDate.toggle()},
				"To "
				FaIcon('calendar-o')

				DateSpanPicker({
					ref: (node) => @endDate = node
					type: 'endDate'
					date: endDate
					historyEntries
					onSelect
				})
			)
		]


	DateSpanPicker = React.createFactory React.createClass
		displayName: 'DateSpanPicker'

		propTypes: {
			type: PropTypes.string.isRequired
			date: PropTypes.instanceOf Moment()
			historyEntries: PropTypes.instanceOf Imm.List()
		}

		componentDidMount: ->
			@_initDateTimePicker()

		_initDateTimePicker: ->
			@datepickerInstance.destroy() if @datepickerInstance?

			{historyEntries} = @props

			#	historyEntries are in reverse-order
			minDate = makeMoment(historyEntries.last().get('timestamp')).startOf 'day'
			maxDate = makeMoment(historyEntries.first().get('timestamp')).startOf 'day'

			$(@dateInput).datetimepicker({
				format: 'Do MMM'
				defaultDate: @props.date or null
				showClose: true
				minDate
				maxDate
				toolbarPlacement: 'bottom'
				widgetPositioning: {
					vertical: 'bottom'
					horizontal: 'right'
				}
			}).on 'dp.change', ({date}) => @props.onSelect(@props.type, date)

			@datepickerInstance = $(@dateInput).data('DateTimePicker')

		toggle: ->
			@datepickerInstance.toggle()

		componentWillUnmount: ->
			@datepickerInstance.destroy()

		componentWillReceiveProps: (newProps) ->
			unless Imm.is newProps.historyEntries, @props.historyEntries
				@_initDateTimePicker()

		render: ->
			R.span({className: 'dateSpanPicker'},
				R.input({
					ref: (node) => @dateInput = node
					style: {
						width: '75px'
						display: 'none'
					}
				})

				@props.date.format('Do MMM') if @props.date
			)





	return FilterBar

module.exports = {load}