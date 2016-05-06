# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Read/Write event information view contained within eventTab

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	Bootbox = win.bootbox

	B = require('../utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

	Moment = require 'moment'
	_ = require 'underscore'
	Term = require '../term'

	ExpandingTextArea = require('../expandingTextArea').load(win)
	{FaIcon, renderName, showWhen} = require('../utils').load(win)
	{TimestampFormat} = require '../persist/utils'

	EventTabView = React.createFactory React.createClass
		displayName: 'EventTabView'
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			# Use backdate instead of current date (if exists)
			if @props.backdate
				startDate = Moment(@props.backdate, TimestampFormat)
			else
				startDate = Moment()

			return {
				title: ''
				description: ''
				typeId: ''

				startDate
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
				defaultDate: @state.startDate.toDate()
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
				minDate: @state.startDate.toDate()
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

		componentDidUpdate: (oldProps, oldState) ->
			# Provide parent with relatedElement isBeingEdited
			if oldProps.isBeingEdited isnt @props.isBeingEdited and @props.isBeingEdited and @state.relatedElement
				@props.selectEventPlanRelation @state.relatedElement
				@props.updateEventPlanRelationMode false

		render: ->
			selectedEventType = @props.eventTypes.find (type) => type.get('id') is @state.typeId

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
					# R.div({className: 'form-group planRelationContainer'},
					# 	R.label({}, "Relationship to Plan")
					# 	DropdownButton({
					# 		title: (
					# 			if @props.selectedEventPlanRelation? and @props.selectedEventPlanRelation.get('name')?
					# 				@props.selectedEventPlanRelation.get('name')
					# 			else 
					# 				"No Relationship"
					# 		)
					# 		onToggle: @props.updateEventPlanRelationMode
					# 	},
					# 		(if @props.selectedEventPlanRelation?
					# 			[
					# 				R.li({
					# 					onClick: @props.selectEventPlanRelation.bind null, null
					# 					onMouseOver: @props.hoverEventPlanRelation.bind null, null
					# 				}, 
					# 					R.a({},
					# 						"None "
					# 						FaIcon('ban')
					# 					)
					# 				)
					# 				MenuItem({divider: true})
					# 			]
					# 		)							
					# 		(@props.progNote.get('units').map (unit) =>
					# 			switch unit.get('type')
					# 				when 'basic'
					# 					R.li({
					# 						key: unit.get('id')
					# 						onClick: @props.selectEventPlanRelation.bind null, unit
					# 						onMouseOver: @props.hoverEventPlanRelation.bind null, unit
					# 					}, 
					# 						R.a({}, unit.get('name'))
					# 					)
					# 				when 'plan'
					# 					([
					# 						(unit.get('sections').map (section) =>
					# 							([
					# 								R.li({
					# 									className: 'section'
					# 									key: section.get('id')
					# 									onClick: @props.selectEventPlanRelation.bind null, section
					# 									onMouseOver: @props.hoverEventPlanRelation.bind null, section
					# 								},
					# 									R.a({}, section.get('name'))
					# 								)

					# 								(section.get('targets').map (target) =>
					# 									R.li({
					# 										className: 'target'
					# 										key: target.get('id')
					# 										onClick: @props.selectEventPlanRelation.bind null, target
					# 										onMouseOver: @props.hoverEventPlanRelation.bind null, target
					# 									},
					# 										R.a({}, target.get('name'))
					# 									)
					# 								)
					# 							])
					# 						)
					# 						MenuItem({divider: true})
					# 					])
					# 		)
					# 	)
					# )
					
					unless @props.eventTypes.isEmpty()
						R.div({className: 'form-group eventTypeContainer'},
							R.label({}, "Select #{Term 'Event Type'}")
							
							B.DropdownButton({
								title: if selectedEventType? then selectedEventType.get('name') else "No Type"
							},
								if selectedEventType?
									[
										B.MenuItem({
											onClick: @_updateTypeId.bind null, ''
										}, 
											"None "
											FaIcon('ban')
										)
										B.MenuItem({divider: true})
									]

								(@props.eventTypes.map (eventType) =>
									B.MenuItem({
										key: eventType.get('id')
										onClick: @_updateTypeId.bind null, eventType.get('id')
									}, 
										R.div({
											onClick: @_updateTypeId.bind null, eventType.get('id')
											style:
												borderRight: "5px solid #{eventType.get('colorKeyHex')}"
										},
											eventType.get('name')
										)
									)
								)
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

		_updateTypeId: (typeId) ->
			@setState {typeId}

		_closeForm: (event) ->
			event.preventDefault()

			if (
				@state.title or @state.endDate or @state.description or
				@props.selectedEventPlanRelation or @state.typeId
			)
				Bootbox.confirm "Cancel #{Term 'event'} editing?", (result) =>
					if result
						# Make sure all states are reset, then cancel
						@setState @props.data, =>
							@props.cancel @props.atIndex
			else
				@setState @props.data, =>
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


			if @props.selectedEventPlanRelation?
				# Figure out which element type it is
				relatedElementType = if @props.selectedEventPlanRelation.has('type')
						'progNoteUnit'
					else if @props.selectedEventPlanRelation.has('targets')
						'planSection'
					else if @props.selectedEventPlanRelation.has('metrics')
						'planTarget'
					else
						null
						console.error "Unknown relatedElementType:", @props.selectedEventPlanRelation.toJS()

				relatedElement = {
					id: @props.selectedEventPlanRelation.get('id')
					type: relatedElementType
				}

			else
				relatedElement = ''

			# Provide relatedElement to local state for later
			@setState => {relatedElement: @props.selectedEventPlanRelation}

			progEventObject = {	
				title: @state.title
				description: @state.description
				typeId: @state.typeId
				relatedElement
				startTimestamp: startTimestamp.format(TimestampFormat)
				endTimestamp: if @state.isDateSpan or isOneFullDay then endTimestamp.format(TimestampFormat) else ''
			}

			return progEventObject

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