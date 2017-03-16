# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Toolbar for handling search query (via props and internal copy),
# and a dropdown menu handling selection for options within each filter type

_ = require 'underscore'
Imm = require 'immutable'

Term = require '../term'


load = (win) ->
	React = win.React
	{PropTypes} = React
	{findDOMNode} = win.ReactDOM
	R = React.DOM

	ColorKeyBubble = require('../colorKeyBubble').load(win)
	{FaIcon, showWhen} = require('../utils').load(win)


	FilterBar = React.createFactory React.createClass
		displayName: 'FilterBar'
		mixins: [React.addons.PureRenderMixin]

		propTypes: {
			# TODO: isRequired?
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
						onSelect: (->)
					},
						R.li({}, "Whatup?")
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
			buttonChildren = Array.from findDOMNode @refs.menuButton
			optionsListChildren = Array.from findDOMNode @refs.optionsList

			# Check for inside/outside click
			if buttonChildren.contains event.target
				@_toggleIsOpen()
			else if not optionsListChildren.contains event.target
				@setState {isOpen: false}
			else
				console.warn "Unknown document click..?"

		_toggleIsOpen: ->
			@setState {isOpen: not @state.isOpen}

		render: ->
			{title, dataOptions, selectedValue, onSelect} = @props
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
							className: 'selectAllOption'
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
								onSelect
							})
					)
				)

				# Visible option either shows
				R.div({
					ref: 'menuButton'
					className: 'option selectedValue'
				},
					(if hasSelection
						FilterOption({
							option: selectedOption
							onSelect
						})
					else
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






	return FilterBar

module.exports = {load}