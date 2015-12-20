# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Read/Write event information view contained within eventTab

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Bootbox = win.bootbox	

	Moment = require 'moment'
	_ = require 'underscore'
	Term = require '../term'

	ExpandingTextArea = require('../expandingTextArea').load(win)
	{FaIcon, renderName, showWhen} = require('../utils').load(win)
	{TimestampFormat} = require '../persist/utils'

	EventTabView = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				title: ''
				description: ''

				startDate: Moment()
				startTime: ''
				endDate: ''
				endTime: ''

				isDateSpan: false
				usesTimeOfDay: false
			}

		componentDidMount: ->
			# Initialize datepickers, bind to @state

			# Grab jQ contexts
			$startDate = $(@refs.startDate)
			$startTime = $(@refs.startTime)
			$endDate = $(@refs.endDate)
			$endTime = $(@refs.endTime)

			$startDate.datetimepicker({
				useCurrent: false
				format: 'Do MMM, \'YY'
				defaultDate: Moment()
				widgetPositioning: {
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				$endDate.data('DateTimePicker').minDate(thisInput.date)
				@setState {startDate: thisInput.date}

			$startTime.datetimepicker({
				useCurrent: false
				format: 'hh:mm a'
				widgetPositioning: {					
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>				
				@setState {startTime: thisInput.date}


			$endDate.datetimepicker({
				minDate: Moment()
				useCurrent: false
				format: 'Do MMM, \'YY'
				widgetPositioning: {					
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				$startDate.data('DateTimePicker').maxDate(thisInput.date)
				@setState {endDate: thisInput.date}

			$endTime.datetimepicker({
				useCurrent: false
				format: 'hh:mm a'
				widgetPositioning: {					
					horizontal: 'right'
				}
			}).on 'dp.change', (thisInput) =>
				@setState {endTime: thisInput.date}


		render: ->
			return R.div({
				className: "eventView #{showWhen @props.isBeingEdited or not @props.editMode}"
			},
				R.form({className: showWhen @props.isBeingEdited},
					R.button({
						className: 'btn btn-danger closeButton'
						onClick: @_closeForm
					}, 
						FaIcon('times')
					)
					R.div({className: 'form-group'},
						R.label({}, "Name")
						R.input({
							id: 'nameInput'
							className: 'form-control'
							value: @state.title
							onChange: @_updateTitle
							placeholder: "Name of #{Term 'event'}"
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Description")
						ExpandingTextArea({
							value: @state.description
							onChange: @_updateDescription
							placeholder: "Describe details (optional)"
						})
					)
					R.div({className: 'form-group'},
						R.label({}, "Plan Relation")
						R.select({},
							R.option({}, "No Relation")
							(@props.progNote.get('units').map (unit) =>
								switch unit.get('type')
									when 'basic'
										R.option({}, unit.get('name'))
									when 'plan'
										R.optgroup({label: unit.get('name')},
											(unit.get('sections').map (section) =>
												R.option({},
													section.get('name')
													(section.get('targets').map (target) =>
														R.option({}, "- #{target.get('name')}")
													)
												)
											)
										)
							)
						)
						R.div({},
							R.a({onClick: @_toggleEventRelationMode}, "Select from plan")
						)
					)
					R.div({className: "dateGroup"},
						R.div({className: 'form-group date'},
							R.label({}, if @state.isDateSpan then "Start Date" else "Date")
							R.input({
								ref: 'startDate'
								className: 'form-control'
								type: 'text'
							})
						)
						R.div({className: "form-group timeOfDay #{showWhen @state.usesTimeOfDay}"},
							R.label({},
								R.span({onClick: @_toggleUsesTimeOfDay},
									FaIcon('clock-o')
									FaIcon('times')
								)
							)
							R.input({
								ref: 'startTime'
								className: 'form-control'
								type: 'text'
								placeholder: "00:00 --"
							})						
						)
						R.div({className: "form-group useTimeOfDay #{showWhen not @state.usesTimeOfDay}"}
							R.button({
								className: 'btn btn-default'									
								onClick: @_toggleUsesTimeOfDay
							}, FaIcon('clock-o'))
						)
					)					
					R.div({className: "dateGroup #{showWhen @state.isDateSpan}"},
						R.div({
							className: 'form-group removeDateSpan'							
						}
							R.span({onClick: @_toggleIsDateSpan},
								FaIcon('arrow-right')
								FaIcon('times')
							)							
						)
						R.div({className: 'form-group date'},
							R.label({}, "End Date")
							R.input({
								ref: 'endDate'
								className: 'form-control'
								type: 'text'
								placeholder: "Select date"
							})
						)
						R.div({className: "form-group timeOfDay #{showWhen @state.usesTimeOfDay}"},
							R.label({},
								R.span({onClick: @_toggleUsesTimeOfDay},
									FaIcon('clock-o')
									FaIcon('times')
								)
							)
							R.input({
								ref: 'endTime'
								className: 'form-control'
								type: 'text'
								placeholder: "00:00 --"
							})						
						)
						R.div({className: "form-group useTimeOfDay #{showWhen not @state.usesTimeOfDay}"}
							R.button({
								className: 'btn btn-default'
								onClick: @_toggleUsesTimeOfDay
							}, FaIcon('clock-o'))
						)
					)
					R.div({
						className: 'btn-toolbar'
					},
						R.button({
							className: "btn btn-default #{showWhen not @state.isDateSpan}"
							onClick: @_toggleIsDateSpan
						},
							"Add End Date"
						)
						R.button({
							className: "btn btn-success #{'fullWidth' if @state.isDateSpan}"
							type: 'submit'
							onClick: @_saveEventData
							disabled: not @state.title or not @state.startDate or (@state.isDateSpan and not @state.endDate) or (@state.usesTimeOfDay and not @state.startTime) or (@state.usesTimeOfDay and @state.isDateSpan and not @state.endTime)
						}, 
							"Save "
							FaIcon('check')
						)
					)					
				)

				R.div({className: "details #{showWhen not @props.isBeingEdited}"},
					R.div({className: 'title'}, @props.data.title)
					R.div({className: 'description'}, @props.data.description)
					R.div({className: 'timeSpan'},
						R.div({className: 'start'}, 
							"From: " if @props.data.endTimestamp
							@_showTimestamp @props.data.startTimestamp
						)
						(if @props.data.endTimestamp
							R.div({className: 'end'}, 
								"Until: "
								@_showTimestamp @props.data.endTimestamp
							)
						)
					)
				)				
		)

		_toggleUsesTimeOfDay: (event) ->
			event.preventDefault()
			@setState {usesTimeOfDay: not @state.usesTimeOfDay}, =>
				# Focus timeInput if enabling
				# if @state.usesTimeOfDay
				# 	@refs[timeInput].focus()

		_showTimestamp: (timestamp) ->
			moment = Moment(timestamp, TimestampFormat)

			if moment.isValid
				return Moment(moment, TimestampFormat).format('Do MMMM [at] h:mm A')
			else
				return "Invalid Moment"

		_toggleIsDateSpan: (event) ->
			event.preventDefault()
			@setState {isDateSpan: not @state.isDateSpan}, =>
				# Focus endDate if enabling
				if @state.isDateSpan
					@refs.endDate.focus()

		_updateTitle: (event) ->
			@setState {title: event.target.value}

		_updateDescription: (event) ->
			@setState {description: event.target.value}

		_toggleEventRelationMode: ->
			if @props.selectedEventRelation?				
				@props.selectEventRelation null # Cancels eventRelationMode
			else
				@props.selectEventRelation false # Instantiates it

		_closeForm: (event) ->
			event.preventDefault()

			if (@state.startDate or @state.endDate or @state.description)
				Bootbox.confirm "Cancel #{Term 'event'} editing?", (result) =>
					if result
						# Make sure all states are reset, then cancel
						@replaceState @props.data, =>
							@props.cancel @props.atIndex
			else
				@replaceState @props.data, =>
					@props.cancel @props.atIndex

		_compiledFormData: ->
			isOneFullDay = null

			# Start with dates
			startTimestamp = @state.startDate
			endTimestamp = @state.endDate

			# Extract time from start/endTime
			if @state.usesTimeOfDay
				startTimestamp = startTimestamp.set('hour', @state.startTime.hour()).set('minute', @state.startTime.minute())

				if @state.isDateSpan
					endTimestamp = endTimestamp.set('hour', @state.endTime.hour()).set('minute', @state.endTime.minute())
			# Default to start/end of day for dates
			else
				startTimestamp = startTimestamp.startOf('day')

				if @state.isDateSpan					
					endTimestamp = endTimestamp.endOf('day')
				else
					# If only a single date was provided, assume it's an all-day event
					isOneFullDay = true
					endTimestamp = Moment(startTimestamp).endOf('day')

			return {	
				title: @state.title
				description: @state.description
				startTimestamp: startTimestamp.format(TimestampFormat)
				endTimestamp: if @state.isDateSpan or isOneFullDay then endTimestamp.format(TimestampFormat) else ''
			}

		_saveEventData: (event) ->
			event.preventDefault()

			newData = @_compiledFormData()

			unless newData.endTimestamp.length is 0
				startTimestamp = Moment(newData.startTimestamp, TimestampFormat)
				endTimestamp = Moment(newData.endTimestamp, TimestampFormat)

				# Ensure startTime is earlier than endTime
				if startTimestamp.isAfter endTimestamp
					startDateTime = startTimestamp.format('Do MMMM [at] h:mm A')
					Bootbox.alert "Please select an end date/time later than #{startDateTime}"
					return

			@props.save newData, @props.atIndex

	return EventTabView

module.exports = {load}