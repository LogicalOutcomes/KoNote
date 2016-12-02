# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

_ = require 'underscore'
Imm = require 'immutable'

Term = require '../term'


load = (win) ->
	React = win.React
	{PropTypes} = React
	R = React.DOM

	ColorKeyBubble = require('../colorKeyBubble').load(win)
	{FaIcon, showWhen} = require('../utils').load(win)

	dataTypeOptions = Imm.fromJS [
		{name: 'Progress Notes', id: 'progNotes'}
		{name: 'Targets', id: 'targets'}
		{name: 'Events', id: 'events'}
	]


	FilterBar = React.createFactory React.createClass
		displayName: 'FilterBar'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			onUpdateSearchQuery: PropTypes.func
			programIdFilter: PropTypes.string
			dataTypeFilter: PropTypes.oneOf ['progNotes', 'targets', 'events']
			programsById: PropTypes.instanceOf Imm.List()

			onClose: PropTypes.func
			onUpdateSearchQuery: PropTypes.func
			onSelectProgramId: PropTypes.func
			onSelectDataType: PropTypes.func
		}

		getInitialState: -> {
			searchText: '' # Stays internal for perf reasons
		}

		componentWillMount: ->
			# Sparingly update the parent progNotesTab UI
			@_updateSearchQuery = _.debounce(@props.onUpdateSearchQuery, 350)

		componentDidMount: ->
			@_focusInput()

		componentDidUpdate: (oldProps, oldState) ->
			# Focus input when made visible
			if @props.isVisible isnt oldProps.isVisible and @props.isVisible
				@_focusInput()

		_focusInput: ->
			@refs.searchText.focus()

		_updateSearchText: (event) ->
			searchText = event.target.value

			@setState {searchText}
			@_updateSearchQuery(searchText)

		render: ->
			R.div({
				className: "filterBar #{showWhen @props.isVisible}"
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
				R.section({},
					FilterDropdownMenu({
						title: 'Data'
						selectedValue: @props.dataTypeFilter
						dataOptions: dataTypeOptions
						onSelect: @props.onSelectDataType
					})
					FilterDropdownMenu({
						title: Term 'Programs'
						selectedValue: @props.programIdFilter
						dataOptions: @props.programsById
						onSelect: @props.onSelectProgramId
					})
					R.div({
						className: 'closeButton'
						onClick: @props.onClose
					},
						FaIcon('times-circle')
					)
				)
			)

	FilterDropdownMenu = React.createFactory React.createClass
		displayName: 'FilterDropdownMenu'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {isOpen: false}

		_toggleIsOpen: ->
			@setState {isOpen: not @state.isOpen}

		_onSelect: (value) ->
			@props.onSelect(value)
			@_toggleIsOpen()

		_renderOption: (option) ->
			selectedOption = option or @props.dataOptions.find (o) =>
				o.get('id') is @props.selectedValue

			return R.span({},
				(if selectedOption.has 'colorKeyHex'
					ColorKeyBubble({
						colorKeyHex: selectedOption.get('colorKeyHex')
					})
				)
				R.span({className: 'value'},
					selectedOption.get('name')
				)
			)

		render: ->
			{title, dataOptions, selectedValue} = @props
			hasSelection = !!selectedValue

			filteredDataOptions = if hasSelection
				# Filter out selected type
				dataOptions.filterNot (o) -> o.get('id') is selectedValue
			else
				dataOptions


			R.div({
				className: [
					'filterDropdownMenu'
					'isOpen' if @state.isOpen
				].join ' '
				onMouseEnter: @_toggleIsOpen unless @state.isOpen
				onMouseLeave: @_toggleIsOpen if @state.isOpen
			},
				R.ul({className: 'filterOptions'},
					(if hasSelection
						R.li({
							className: 'selectAllOption'
							onClick: @_onSelect.bind null, null
						},
							"All #{title}"
						)
					)

					(filteredDataOptions.toSeq().map (option) =>
						R.li({
							onClick: @_onSelect.bind null, option.get('id')
						},
							@_renderOption(option)
						)
					)
				)
				R.div({className: 'selectedValue'},
					(if hasSelection
						@_renderOption()
					else
						"All #{title}"
					)
					' '
					FaIcon('caret-down')
				)
			)


	return FilterBar

module.exports = {load}