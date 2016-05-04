# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# The Plan tab on the client file page.

Async = require 'async'
Imm = require 'immutable'
Moment = require 'moment'
_ = require 'underscore'

Config = require '../config'
Term = require '../term'
Persist = require '../persist'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	ModifyTargetStatusDialog = require('./modifyTargetStatusDialog').load(win)
	CrashHandler = require('../crashHandler').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	WithTooltip = require('../withTooltip').load(win)
	MetricLookupField = require('../metricLookupField').load(win)
	MetricWidget = require('../metricWidget').load(win)
	OpenDialogLink = require('../openDialogLink').load(win)
	PrintButton = require('../printButton').load(win)
	{FaIcon, renderLineBreaks, showWhen, stripMetadata} = require('../utils').load(win)

	PlanView = React.createFactory React.createClass
		displayName: 'PlanView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				plan: @props.plan
				selectedTargetId: null
				currentTargetRevisionsById: @_generateCurrentTargetRevisionsById @props.planTargetsById
			}

		componentWillReceiveProps: (newProps) ->
			# Regenerate transient data when plan is updated
			unless Imm.is(newProps.plan, @props.plan)
				@setState {
					plan: newProps.plan
					currentTargetRevisionsById: @_generateCurrentTargetRevisionsById newProps.planTargetsById
				}

			# Regenerate targetRevisions when target changed
			unless Imm.is(newProps.planTargetsById, @props.planTargetsById)
				console.log "planTargetsById updated!"
				@setState {
					currentTargetRevisionsById: @_generateCurrentTargetRevisionsById newProps.planTargetsById
				}

		_generateCurrentTargetRevisionsById: (planTargetsById) ->
			return planTargetsById.mapEntries ([targetId, target]) =>
				latestRev = stripMetadata target.get('revisions').first()
				return [targetId, latestRev]

		render: ->
			plan = @state.plan

			# If something selected and that target has not been deleted
			if @state.selectedTargetId? and @state.currentTargetRevisionsById.has(@state.selectedTargetId)
				# If this target has been saved at least once
				if @props.planTargetsById.has @state.selectedTargetId
					selectedTarget = @props.planTargetsById.get @state.selectedTargetId
				else
					# New target with no revision history
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
							"This #{Term 'client'} does not currently have any #{Term 'plan targets'}."
						)						
						R.button({
							className: 'addSection btn btn-success btn-lg'
							onClick: @_addSection
							disabled: @props.isReadOnly
						},
							FaIcon('plus')
							"Add #{Term 'section'}"
						)
					)
					R.div({className: "toolbar #{showWhen plan.get('sections').size > 0}"},
						R.span({className: 'leftMenu'},
							R.button({
								className: [
									'save btn'
									if @hasChanges() then 'btn-success canSave'
								].join ' '
								disabled: not @hasChanges() or @props.isReadOnly
								onClick: @_save
							},
								FaIcon('save')
								"Save #{Term 'Plan'}"
							)	
						)
						R.span({className: 'rightMenu'},							
							R.button({
								className: 'addSection btn btn-default'
								onClick: @_addSection
								disabled: @props.isReadOnly
							},
								FaIcon('plus')
								"Add #{Term 'section'}"
							)
							PrintButton({
								dataSet: [
									{
										format: 'plan'
										data: {
											sections: plan.get('sections')
											targets: @state.currentTargetRevisionsById
											metrics: @props.metricsById
										}
										clientFile: @props.clientFile
									}
								]
								iconOnly: true
								disabled: @hasChanges()
								tooltip: {
									show: @hasChanges()
									placement: 'bottom'
									title: "Please save the changes to #{Term 'client'}'s #{Term 'plan'} before printing"
								}
							})					
						)
					)
					SectionsView({
						plan: @state.plan
						metricsById: @props.metricsById
						currentTargetRevisionsById: @state.currentTargetRevisionsById
						selectedTargetId: @state.selectedTargetId
						isReadOnly: @props.isReadOnly

						renameSection: @_renameSection
						addTargetToSection: @_addTargetToSection
						hasTargetChanged: @_hasTargetChanged
						updateTarget: @_updateTarget
						setSelectedTarget: @_setSelectedTarget
					})
				)
				R.div({className: 'targetDetail'},
					(if not selectedTarget?
						R.div({className: "noSelection #{showWhen plan.get('sections').size > 0}"},
							"More information will appear here when you select ",
							"a #{Term 'target'} on the left."
						)
					else
						currentRev = @state.currentTargetRevisionsById.get(selectedTarget.get('id'))
						metricDefs = currentRev.get('metricIds').map (metricId) =>
							return @props.metricsById.get(metricId, null)

						R.div({className: 'targetDetailContainer'},
							R.div({className: 'metricsSection'},
								R.div({className: 'header'},
									R.div({className: 'text'}, Term('Metrics'))
								)
								(if metricDefs.size is 0
									R.div({className: 'noMetrics'},
										"This #{Term 'target'} has no #{Term 'metrics'} attached."
										(unless @props.isReadOnly
											R.button({
												className: 'btn btn-link addMetricButton'
												onClick: @_focusMetricLookupField
											}, FaIcon('plus'))
										)
									)									
								else
									R.div({className: 'metrics'},
										(metricDefs.map (metricDef) =>
											MetricWidget({
												isEditable: false
												allowDeleting: not @props.isReadOnly
												onDelete: @_deleteMetricFromTarget.bind(
													null, selectedTarget.get('id'), metricDef.get('id')
												)
												key: metricDef.get('id')
												name: metricDef.get('name')
												definition: metricDef.get('definition')
											})
										).toJS()...
										(unless @props.isReadOnly
											R.button({
												className: 'btn btn-link addMetricButton'
												onClick: @_focusMetricLookupField
											}, FaIcon('plus'))
										)
									)
								)
								(unless @props.isReadOnly
									R.div({},
										MetricLookupField({
											metrics: @props.metricsById.valueSeq()
											onSelection: @_addMetricToTarget.bind(
												null, selectedTarget.get('id')
											)
											placeholder: "Find / Define a #{Term 'Metric'}"
											isReadOnly: @props.isReadOnly
										})
									)
								)
							)
							PlanTargetHistory({
								revisions: selectedTarget.get('revisions')
							})
						)
					)
				)
			)

		_focusMetricLookupField: -> $('.lookupField').focus()

		blinkUnsaved: ->			
			toggleBlink = -> $('.hasChanges').toggleClass('blink')
			secondBlink = ->
				toggleBlink()
				setTimeout(toggleBlink, 500)

			setTimeout(secondBlink, 750)

		hasChanges: ->
			# If there is a difference, then there have been changes
			unless Imm.is @props.plan, @state.plan
				return true

			for targetId in @state.currentTargetRevisionsById.keySeq().toJS()
				if @_hasTargetChanged targetId
					return true

			return false

		_hasTargetChanged: (targetId) ->
			currentRev = @_normalizeTarget @state.currentTargetRevisionsById.get(targetId)

			# If this is a new target
			target = @props.planTargetsById.get(targetId, null)
			unless target
				# If target is empty
				emptyName = currentRev.get('name') is ''
				emptyDescription = currentRev.get('description') is ''
				if emptyName and emptyDescription
					return false

				return true

			lastRev = target.getIn ['revisions', 0]

			lastRevNormalized = lastRev
				.delete('revisionId')
				.delete('author')
				.delete('timestamp')

			return not Imm.is(currentRev, lastRevNormalized)

		_save: ->
			@_normalizeTargets()
			@_removeUnusedTargets()

			# Wait for state changes to be applied
			@forceUpdate =>
				valid = @_validateTargets()

				unless valid
					Bootbox.alert "Cannot save #{Term 'plan'}: there are empty #{Term 'target'} fields."
					return

				newPlanTargets = @state.currentTargetRevisionsById.valueSeq()
				.filter (target) =>
					# Only include targets that have not been saved yet
					return not @props.planTargetsById.has(target.get('id'))
				.map(@_normalizeTarget)

				updatedPlanTargets = @state.currentTargetRevisionsById.valueSeq()
				.filter (target) =>
					# Ignore new targets
					unless @props.planTargetsById.has(target.get('id'))
						return false

					# Only include targets that have actually changed
					return @_hasTargetChanged target.get('id')
				.map(@_normalizeTarget)

				@props.updatePlan @state.plan, newPlanTargets, updatedPlanTargets

		_normalizeTargets: ->
			@setState (state) =>
				return {
					currentTargetRevisionsById: state.currentTargetRevisionsById
					.map (targetRev, targetId) =>
						return @_normalizeTarget targetRev
				}

		_normalizeTarget: (targetRev) ->
			trim = (s) -> s.trim()

			# Trim whitespace from fields
			return targetRev
			.update('name', trim)
			.update('description', trim)

		_removeUnusedTargets: ->
			@setState (state) =>
				unusedTargetIds = state.plan.get('sections').flatMap (section) =>
					return section.get('targetIds').filter (targetId) =>
						currentRev = state.currentTargetRevisionsById.get(targetId)

						emptyName = currentRev.get('name') is ''
						emptyDescription = currentRev.get('description') is ''
						noMetrics = currentRev.get('metricIds').size is 0
						noHistory = @props.planTargetsById.get(targetId, null) is null

						return emptyName and emptyDescription and noMetrics and noHistory

				return {
					plan: state.plan.update 'sections', (sections) =>
						return sections.map (section) =>
							return section.update 'targetIds', (targetIds) =>
								return targetIds.filter (targetId) =>
									return not unusedTargetIds.contains(targetId)

					currentTargetRevisionsById: state.currentTargetRevisionsById
					.filter (rev, targetId) =>
						return not unusedTargetIds.contains(targetId)
				}

		_validateTargets: -> # returns true iff all valid
			return @state.plan.get('sections').every (section) =>
				return section.get('targetIds').every (targetId) =>
					currentRev = @state.currentTargetRevisionsById.get(targetId)

					emptyName = currentRev.get('name') is ''
					emptyDescription = currentRev.get('description') is ''

					return not emptyName and not emptyDescription

		_addSection: ->
			sectionId = Persist.generateId()

			Bootbox.prompt "Enter a name for the new #{Term 'section'}:", (sectionName) =>
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

		_renameSection: (sectionId) ->
			sectionIndex = @_getSectionIndex sectionId
			sectionName = @state.plan.getIn ['sections', sectionIndex, 'name']

			Bootbox.prompt 'Enter a new name for "' + sectionName + '"', (newSectionName) =>
				newSectionName = newSectionName?.trim()

				unless newSectionName
					return

				newPlan = @state.plan.setIn ['sections', sectionIndex, 'name'], newSectionName
				@setState {plan: newPlan}

		_addTargetToSection: (sectionId) ->
			sectionIndex = @_getSectionIndex sectionId

			targetId = '__transient__' + Persist.generateId()
			newPlan = @state.plan.updateIn ['sections', sectionIndex, 'targetIds'], (targetIds) =>
				return targetIds.push targetId

			newTarget = Imm.fromJS {
				id: targetId
				clientFileId: @props.clientFileId
				status: 'default'
				name: ''
				description: ''
				metricIds: []
			}
			newCurrentRevs = @state.currentTargetRevisionsById.set targetId, newTarget

			@setState {
				plan: newPlan
				currentTargetRevisionsById: newCurrentRevs
			}, =>
				# Temporary until we work out a Bootbox alternative
				setTimeout(=>
					$(".target-#{targetId} .name.field").focus()
				, 250)

		_getSectionIndex: (sectionId) ->
			return @state.plan.get('sections').findIndex (section) =>
				return section.get('id') is sectionId

		_updateTarget: (targetId, newValue) ->
			@setState {
				currentTargetRevisionsById: @state.currentTargetRevisionsById.set targetId, newValue
			}

		_setSelectedTarget: (targetId) ->
			@setState {selectedTargetId: targetId}

		_addMetricToTarget: (targetId, metricId) ->			
			# Current target already has this metric
			if @state.currentTargetRevisionsById.getIn([targetId, 'metricIds']).contains metricId
				Bootbox.alert "This #{Term 'metric'} has already been added to the selected #{Term 'target'}."
				return

			# Metric exists in another target
			existsElsewhere = @state.currentTargetRevisionsById.some (target) =>
				return target.get('metricIds').contains(metricId)
			if existsElsewhere
				Bootbox.alert "This #{Term 'metric'} already exists for another #{Term 'plan target'}"
				return

			@setState {
				currentTargetRevisionsById: @state.currentTargetRevisionsById.update targetId, (currentRev) ->
					return currentRev.update 'metricIds', (metricIds) ->
						return metricIds.push metricId
			}

		_deleteMetricFromTarget: (targetId, metricId) ->
			@setState {
				currentTargetRevisionsById: @state.currentTargetRevisionsById.update targetId, (currentRev) ->
					return currentRev.update 'metricIds', (metricIds) ->
						return metricIds.filter (id) ->
							return id isnt metricId
			}

	SectionsView = React.createFactory React.createClass
		displayName: 'SectionsView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				sectionsScrollTop: 0
				sectionOffsets: null
			}

		componentDidMount: ->
			sectionsDom = @refs.sections
			sectionsDom.addEventListener 'scroll', (event) =>
				@_recalculateOffsets()

		_recalculateOffsets: ->
			sectionsDom = @refs.sections
			sectionsScrollTop = sectionsDom.scrollTop

			sectionOffsets = @props.plan.get('sections').map (section) =>
				sectionDom = @refs['section-' + section.get('id')]

				offset = Imm.Map({
					top: sectionDom.offsetTop
					height: sectionDom.offsetHeight
				})

				return [section.get('id'), offset]
			.fromEntrySeq().toMap()

			@setState (s) -> {sectionsScrollTop, sectionOffsets}

		render: ->
			{
				plan
				metricsById
				currentTargetRevisionsById
				selectedTargetId
				isReadOnly

				renameSection
				addTargetToSection
				hasTargetChanged
				updateTarget
				setSelectedTarget
			} = @props

			return R.div({className: 'sections', ref: 'sections'},
				(plan.get('sections').map (section) =>
					headerState = 'inline'

					if @state.sectionOffsets and @state.sectionOffsets.get(section.get('id'))
						scrollTop = @state.sectionsScrollTop
						sectionOffset = @state.sectionOffsets.get(section.get('id'))

						headerHeight = 60
						minSticky = sectionOffset.get('top')
						maxSticky = sectionOffset.get('top') + sectionOffset.get('height') - headerHeight

						if scrollTop >= minSticky and scrollTop < maxSticky
							headerState = 'sticky'

					return R.div({
						className: 'section'
						key: section.get('id')
						ref: 'section-' + section.get('id')
					},
						SectionHeader({
							type: 'inline'
							visible: headerState is 'inline'

							section
							isReadOnly

							renameSection
							addTargetToSection
						})
						SectionHeader({
							type: 'sticky'
							visible: headerState is 'sticky'
							scrollTop: @state.sectionsScrollTop

							section
							isReadOnly

							renameSection
							addTargetToSection
						})
						(if section.get('targetIds').size is 0
							R.div({className: 'noTargets'},
								"This #{Term 'section'} is empty."
							)
						)
						R.div({className: 'targets'},
							# filter here
							# filteredTargets = section.get('targetIds').filter (targetId) =>
							# 	currentRevision = currentTargetRevisionsById.get targetId
							# 	return currentRevision.get('status') is 'default'

							(section.get('targetIds').map (targetId) =>
								PlanTarget({
									currentRevision: currentTargetRevisionsById.get targetId
									metricsById
									hasTargetChanged: hasTargetChanged targetId
									key: targetId
									isActive: targetId is selectedTargetId
									isReadOnly
									onTargetUpdate: updateTarget.bind null, targetId
									onTargetSelection: setSelectedTarget.bind null, targetId
								})
							).toJS()...
						)
					)
				).toJS()...
			)

	SectionHeader = React.createFactory React.createClass
		displayName: 'SectionHeader'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{
				type
				visible
				scrollTop
				section
				isReadOnly

				renameSection
				addTargetToSection
			} = @props

			return R.div({
				className: [
					'sectionHeader'
					type
					'invisible' unless visible
				].join(' ')
				style: {
					top: "#{scrollTop}px" if type is 'sticky'
				}
			},
				R.div({className: 'sectionName'},
					section.get('name')
				)
				R.div({className: 'btn-group btn-group-sm'},
					R.button({
						className: 'renameSection btn btn-default'
						onClick: renameSection.bind null, section.get('id')
						disabled: isReadOnly
					},
						"Rename"
					)
					R.button({
						className: 'addTarget btn btn-primary'
						onClick: addTargetToSection.bind null, section.get('id')
						disabled: isReadOnly
					},
						FaIcon('plus')
						"Add #{Term 'target'}"
					)
				)
			)

	PlanTarget = React.createFactory React.createClass
		displayName: 'PlanTarget'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			currentRevision = @props.currentRevision

			return R.div({
				className: [
					'target'
					"target-#{currentRevision.get('id')}"
					if @props.isActive then 'active' else ''
					if @props.hasTargetChanged then 'hasChanges' else ''
					if @props.isReadOnly then 'readOnly' else ''
				].join ' '
				onClick: @_onTargetClick
			},
				
				R.div({className: 'nameContainer'},
					R.input({
						type: 'text'
						className: 'name field form-control'
						ref: 'nameField'
						placeholder: "Name of #{Term 'target'}"
						value: currentRevision.get('name')
						disabled: @props.isReadOnly
						onChange: @_updateField.bind null, 'name'
						onFocus: @props.onTargetSelection unless @props.isReadOnly
						onClick: @props.onTargetSelection if @props.isReadOnly

					})

					# button to deactivate the target
					unless @props.currentRevision.get('status') is 'cancelled'
						WithTooltip({title: "De-Activate", placement: 'top'},
							OpenDialogLink({
								dialog: ModifyTargetStatusDialog
								target: @props.currentRevision
								newStatus: 'cancelled'
								title: "Deactivate the #{Term 'Target'}"
								reasonLabel: "Reason for deactivation: "
								message: "This will deactivate the #{Term 'Target'}"
								disabled: @props.isReadOnly or @props.hasTargetChanged
							},
								R.a({className: 'cancelled'},
									FaIcon 'ban'
								)
							)
						)

					# button to complete the target
					unless @props.currentRevision.get('status') is 'completed' or 
					@props.currentRevision.get('status') is 'cancelled'
						WithTooltip({title: "Complete", placement: 'top'},
							OpenDialogLink({
								dialog: ModifyTargetStatusDialog
								target: @props.currentRevision
								newStatus: 'completed'
								title: "Complete the #{Term 'Target'}"
								reasonLabel: "Reason for completion: "
								message: "This will complete the #{Term 'Target'}"
								disabled: @props.isReadOnly or @props.hasTargetChanged
							},
								R.a({className: 'completed'},
									FaIcon 'check'
								)
							)
						)

					# button to activate the target
					unless @props.currentRevision.get('status') is 'default'
						WithTooltip({title: "Re-Activate", placement: 'top'},
							OpenDialogLink({
								dialog: ModifyTargetStatusDialog
								target: @props.currentRevision
								newStatus: 'default'
								title: "Activate the #{Term 'Target'}"
								reasonLabel: "Reason for activation: "
								message: "This will activate the #{Term 'Target'}"
								disabled: @props.isReadOnly or @props.hasTargetChanged
							},
								R.a({className: 'activate'},
									FaIcon 'play-circle'
								)
							)
						)			
				)

				# temporarily showing status during development of this feature
				R.div({},
					"status: " 
					@props.currentRevision.get 'status'
				)
				R.div({className: 'descriptionContainer'},
					ExpandingTextArea({
						className: 'description field'
						ref: 'descriptionField'
						placeholder: "Describe the current #{Term 'treatment plan'} . . ."
						value: currentRevision.get('description')
						disabled: @props.isReadOnly
						onChange: @_updateField.bind null, 'description'
						onFocus: @props.onTargetSelection unless @props.isReadOnly
						onClick: @props.onTargetSelection if @props.isReadOnly
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
				@refs.nameField.focus() unless @props.isReadOnly
				@props.onTargetSelection()


	PlanTargetHistory = React.createFactory React.createClass
		displayName: 'PlanTargetHistory'

		propTypes: -> {
			revisions: React.PropTypes.instanceOf Imm.List
		}

		_buildChangeLog: (revision, index) ->
			# Return the regular revision if no previous revision, or they match
			previousRevision = if index > 0 then @props.revisions.get(index - 1) else null
			if not previousRevision? or Imm.is(previousRevision, revision)
				return revision

			# TODO: Generalize this function for arrays & strings,
			# so we (hopefully) don't need to change this when dataModel changes
				
			# Diff the metricIds
			previousMetricIds = previousRevision.get('metricIds')
			currentMetricIds = revision.get('metricIds')

			unless Imm.is previousMetricIds, currentMetricIds
				deletedMetricIds = previousMetricIds
				.filterNot (metricId) -> currentMetricIds.contains(metricId)
				.map (metricId) -> {deleted: metricId}

				addedMetricIds = currentMetricIds
				.filterNot (metricId) -> previousMetricIds.contains(metricId)
				.map (metricId) -> {added: metricId}

				changedMetricIds = deletedMetricIds.concat addedMetricIds				
				revision = revision.set {changedMetricIds}
				console.log "changedMetricIds", changedMetricIds


			# Diff the name
			previousName = previousRevision.get('name')
			currentName = revision.get('name')

			unless previousName is currentName
				changedName = currentName
				revision = revision.set {changedName}
				console.log "changedName", changedName


			# Diff the description
			previousDescription = previousRevision.get('description')
			currentDescription = revision.get('description')

			unless previousDescription is currentDescription
				changedDescription = currentDescription
				revision = revision.set {changedDescription}
				console.log "changedDescription", changedDescription


			return revision

		render: ->
			# Process revision history to devise change logs
			# They're already in reverse-order, so reverse() to map changes
			revisions = @props.revisions
			# TODO: Add this back in for #207 once we have the UI worked out
			# .reverse()
			# .map(@_buildChangeLog)
			# .reverse()

			return R.div({className: 'planTargetHistory'},
				R.div({className: 'heading'},
					'History'
				)
				(if revisions.size is 0
					R.div({className: 'noRevisions'},
						"This #{Term 'target'} is new.  ",
						"It won't have any history until the #{Term 'client file'} is saved."
					)
				)
				R.div({className: 'revisions'},
					(revisions.map (revision) =>
						formattedTimestamp = Moment(revision.get('timestamp'), Persist.TimestampFormat)
						.format('MMM D, YYYY [at] HH:mm')

						R.div({className: 'revision'},
							R.div({className: 'nameLine'},
								R.div({className: 'name'}, revision.get('name'))
								R.div({className: 'tag'},
									formattedTimestamp
									" by "
									revision.get('author')
								)
							)
							R.div({className: 'description'},
								if revision.has('changedMetricIds')
									"Changed: #{JSON.stringify revision.get('changedMetricIds')}"

								renderLineBreaks revision.get('description')
							)
						)
					).toJS()...
				)
			)

	return {PlanView}

module.exports = {load}
