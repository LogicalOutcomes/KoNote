# The Plan tab on the client file page.

Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'

Config = require '../config'
Persist = require '../persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	ExpandingTextArea = require('../expandingTextArea').load(win)
	MetricWidget = require('../metricWidget').load(win)
	{FaIcon, renderLineBreaks, showWhen} = require('../utils').load(win)

	PlanView = React.createFactory React.createClass
		getInitialState: ->
			currentTargetRevisionsById = @props.planTargetsById.mapEntries ([targetId, target]) =>
				latestRev = target.get('revisions').first()
				return [targetId, latestRev]

			return {
				plan: @props.plan
				selectedTargetId: null
				currentTargetRevisionsById
			}
		render: ->
			plan = @state.plan

			if @state.selectedTargetId?
				if @props.planTargetsById.has @state.selectedTargetId
					selectedTarget = @props.planTargetsById.get @state.selectedTargetId
				else
					selectedTarget = Imm.fromJS {
						id: @state.selectedTargetId
						revisions: []
					}
			else
				selectedTarget = null

			return R.div({className: "view planView #{if @props.isVisible then '' else 'hide'}"},
				R.div({className: 'targetList'},
					R.div({className: "empty #{showWhen plan.get('sections').size is 0}"},
						R.div({className: 'message'},
							"This client does not currently have any plan targets. "
						)
						R.button({
							className: 'addSection btn btn-success btn-lg'
							onClick: @_addSection
						},
							FaIcon('plus')
							"Add section"
						)
					)
					R.div({className: "toolbar #{showWhen plan.get('sections').size > 0}"},
						R.button({
							className: 'save btn btn-success'
							disabled: not @_hasChanges()
							onClick: @_save
						},
							FaIcon('save')
							"Save plan"
						)
						R.button({
							className: 'addSection btn btn-default'
							onClick: @_addSection
						},
							FaIcon('plus')
							"Add section"
						)
					)
					R.div({className: 'sections'},
						(plan.get('sections').map (section) =>
							R.div({className: 'section', key: section.get('id')},
								R.div({className: 'sectionHeader'},
									R.div({className: 'sectionName'},
										section.get('name')
									)
									R.button({
										className: 'addTarget btn btn-sm btn-primary'
										onClick: @_addTargetToSection.bind null, section.get('id')
									},
										FaIcon('plus')
										'Add target'
									)
								)
								(if section.get('targetIds').size is 0
									R.div({className: 'noTargets'},
										"This section is empty."
									)
								)
								R.div({className: 'targets'},
									(section.get('targetIds').map (targetId) =>
										PlanTarget({
											currentRevision: @state.currentTargetRevisionsById.get targetId
											metricsById: @props.metricsById
											key: targetId
											isActive: targetId is @state.selectedTargetId
											onTargetUpdate: @_updateTarget.bind null, targetId
											onTargetSelection: @_setSelectedTarget.bind null, targetId
										})
									).toJS()...
								)
							)
						).toJS()...
					)
				)
				R.div({className: 'targetDetail'},
					(if selectedTarget is null
						R.div({className: "noSelection #{showWhen plan.get('sections').size > 0}"},
							"More information will appear here when you select ",
							"a target on the left."
						)
					else
						R.div({className: 'history'},
							R.div({className: 'header'}, 'History')
							(if selectedTarget.get('revisions').size is 0
								R.div({className: 'noRevisions'},
									"This target is new.  ",
									"It won't have any history until the client file is saved."
								)
							)
							R.div({className: 'revisions'},
								(selectedTarget.get('revisions').map (rev) =>
									R.div({className: 'revision'},
										R.div({className: 'nameLine'},
											R.div({className: 'name'},
												rev.get('name')
											)
											R.div({className: 'tag'},
												Moment(rev.get('timestamp'))
													.format('MMM D, YYYY [at] HH:mm'),
												" by ",
												rev.get('author')
											)
										)
										R.div({className: 'notes'},
											renderLineBreaks rev.get('notes')
										)
									)
								).toJS()...
							)
						)
					)
				)
			)
		_hasChanges: ->
			# If there is a difference, then there have been changes
			unless Imm.is @props.plan, @state.plan
				return true

			for targetId in @state.currentTargetRevisionsById.keySeq().toJS()
				if @_hasTargetChanged targetId
					return true

			return false
		_hasTargetChanged: (targetId) ->
			currentRev = @_normalizeTargetFields @state.currentTargetRevisionsById.get(targetId)

			# If this is a new target
			target = @props.planTargetsById.get(targetId, null)
			unless target
				# If target is empty
				emptyName = currentRev.get('name') is ''
				emptyNotes = currentRev.get('notes') is ''
				if emptyName and emptyNotes
					return false

				return true

			lastRev = target.getIn ['revisions', 0]

			if currentRev.get('name') isnt lastRev.get('name')
				return true

			if currentRev.get('notes') isnt lastRev.get('notes')
				return true

			return false
		_normalizeTargetFields: (targetRev) ->
			trim = (s) -> s.trim()

			return targetRev
			.update('name', trim)
			.update('notes', trim)
		_save: ->
			# Validate and clean up targets
			valid = true
			newPlan = @state.plan
			newCurrentRevs = @state.currentTargetRevisionsById
			@state.plan.get('sections').forEach (section, sectionIndex) =>
				newTargetIds = []

				section.get('targetIds').forEach (targetId) =>
					trim = (s) -> s.trim()

					# Trim whitespace from fields
					currentRev = @_normalizeTargetFields newCurrentRevs.get(targetId)
					newCurrentRevs = newCurrentRevs.set targetId, currentRev

					# Remove unused targets
					emptyName = currentRev.get('name') is ''
					emptyNotes = currentRev.get('notes') is ''
					noHistory = @props.planTargetsById.get(targetId, null) is null
					if emptyName and emptyNotes and noHistory
						newCurrentRevs = newCurrentRevs.delete targetId
						return

					# Can't allow this to be saved
					if emptyName or emptyNotes
						valid = false

					newTargetIds.push targetId

				newPlan = newPlan.setIn(
					['sections', sectionIndex, 'targetIds'], Imm.fromJS(newTargetIds)
				)

			@setState {
				plan: newPlan
				currentTargetRevisionsById: newCurrentRevs
			}, =>
				unless valid
					Bootbox.alert 'Cannot save plan: there are empty target fields.'
					return

				# Create new revisions for any plan targets that have changed
				targetIds = @state.currentTargetRevisionsById.keySeq().toJS()
				Async.each targetIds, (targetId, cb) =>
					unless @_hasTargetChanged targetId
						cb null
						return

					currentRev = @_normalizeTargetFields @state.currentTargetRevisionsById.get(targetId)

					@props.registerTask "updateTarget-#{targetId}"
					Persist.PlanTarget.createRevision currentRev, (err) =>
						@props.unregisterTask "updateTarget-#{targetId}"

						if err
							cb err
							return

						cb null
				, (err) =>
					if err
						console.error err.stack
						Bootbox.alert 'An error occurred while saving.'
						return

					# Trigger clientFile save
					@props.updatePlan @state.plan
		_addSection: ->
			sectionId = Persist.generateId()

			Bootbox.prompt 'Enter a name for the new section:', (sectionName) =>
				sectionName = sectionName?.trim()

				unless sectionName
					return

				newPlan = @state.plan.update 'sections', (sections) =>
					return sections.push Imm.fromJS {
						id: sectionId
						name: sectionName
						targetIds: []
					}

				@setState {plan: newPlan}, =>
					@_addTargetToSection sectionId
		_addTargetToSection: (sectionId) ->
			sectionIndex = @_getSectionIndex sectionId

			targetId = Persist.generateId()
			newPlan = @state.plan.updateIn ['sections', sectionIndex, 'targetIds'], (targetIds) =>
				return targetIds.push targetId

			newTarget = Imm.fromJS {
				id: targetId
				clientId: @props.clientId
				name: ''
				notes: ''
				metricIds: []
			}
			newCurrentRevs = @state.currentTargetRevisionsById.set targetId, newTarget

			@setState {
				plan: newPlan
				currentTargetRevisionsById: newCurrentRevs
			}, =>
				$(".target-#{targetId} .name.field").focus()
		_getSectionIndex: (sectionId) ->
			return @state.plan.get('sections').findIndex (section) =>
				return section.get('id') is sectionId
		_updateTarget: (targetId, newValue) ->
			@setState {
				currentTargetRevisionsById: @state.currentTargetRevisionsById.set targetId, newValue
			}
		_setSelectedTarget: (targetId) ->
			@setState {selectedTargetId: targetId}

	PlanTarget = React.createFactory React.createClass
		render: ->
			currentRevision = @props.currentRevision

			return R.div({
				className: [
					'target'
					"target-#{@props.key}"
					if @props.isActive then 'active' else ''
				].join ' '
				onClick: @_onTargetClick
			},
				R.div({className: 'nameContainer'},
					R.input({
						type: 'text'
						className: 'name field form-control'
						ref: 'nameField'
						value: currentRevision.get('name')
						onChange: @_updateField.bind null, 'name'
						onFocus: @props.onTargetSelection
					})
				)
				R.div({className: 'notesContainer'},
					ExpandingTextArea({
						className: 'notes field'
						ref: 'notesField'
						value: currentRevision.get('notes')
						onChange: @_updateField.bind null, 'notes'
						onFocus: @props.onTargetSelection
					})
				)
				R.div({className: 'metrics'},
					(currentRevision.get('metricIds').map (metricId) =>
						metric = @props.metricsById.get(metricId)

						MetricWidget({
							name: metric.get('name')
							definition: metric.get('definition')
							value: metric.get('value')
							key: metricId
						})
					).toJS()...
				)
			)
		_updateField: (fieldName, event) ->
			newValue = @props.currentRevision.set fieldName, event.target.value
			@props.onTargetUpdate newValue
		_onTargetClick: (event) ->
			unless event.target.classList.contains 'field'
				@refs.nameField.getDOMNode().focus()

	return {PlanView}

module.exports = {load}
