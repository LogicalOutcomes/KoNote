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


	FilterBar = React.createFactory React.createClass
		displayName: 'FilterBar'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			onUpdateSearchQuery: PropTypes.func
			programIdFilter: PropTypes.string
			dataTypeFilter: PropTypes.oneOf ['progNotes', 'targets', 'events']
			programsById: PropTypes.instanceOf Imm.List()
			dataTypeOptions: PropTypes.instanceOf Imm.List()

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

		componentWillUpdate: (nextProps, nextState) ->
			# Reset searchText when opening
			if nextProps.isVisible isnt @props.isVisible and nextProps.isVisible
				@setState @getInitialState

		componentDidUpdate: (oldProps, oldState) ->
			# Focus input when made visible
			if @props.isVisible isnt oldProps.isVisible and @props.isVisible
				@_focusInput()

		clear: ->
			@_updateSearchText {target: {value: ''}}
			@props.onSelectProgramId null
			@props.onSelectDataType null
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

		getInitialState: -> {isOpen: false}

		_toggleIsOpen: ->
			@setState {isOpen: not @state.isOpen}

		_onSelect: (value) ->
			@props.onSelect(value)
			@_toggleIsOpen()

		_renderOption: (option) ->
			selectedOption = option or @props.dataOptions.find (o) =>
				o.get('id') is @props.selectedValue

			name = selectedOption.get('name')
			# Specific logic for userProgram icon to appear
			isUserProgram = selectedOption.get('id') is global.ActiveSession.programId

			[
				(if selectedOption.has 'colorKeyHex'
					ColorKeyBubble {
						key: 'bubble'
						colorKeyHex: selectedOption.get('colorKeyHex')
						icon: 'check' if isUserProgram
					}
				)
				R.span({
					key: 'value'
					className: 'value'
				},
					name
				)
			]

		render: ->
			{title, dataOptions, selectedValue} = @props
			hasSelection = !!selectedValue

			if hasSelection
				# Filter out selected type
				dataOptions = dataOptions.filterNot (o) -> o.get('id') is selectedValue


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
							R.span({className: 'value'},
								"All #{title}"
							)
						)
					)

					(dataOptions.toSeq().map (option) =>
						R.li({
							key: option.get('id')
							className: 'option'
							onClick: @_onSelect.bind null, option.get('id')
						},
							@_renderOption(option)
						)
					)
				)
				R.div({className: 'option selectedValue'},
					(if hasSelection
						@_renderOption()
					else
						R.span({className: 'value'},
							"All #{title}"
						)
					)
					' '
					FaIcon('caret-down')
				)
			)


	return FilterBar

module.exports = {load}