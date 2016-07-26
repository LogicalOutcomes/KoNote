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
	ReactDOM = win.ReactDOM

	ModifyTargetStatusDialog = require('./modifyTargetStatusDialog').load(win)
	RevisionHistory = require('../revisionHistory').load(win)
	ModifySectionStatusDialog = require('./modifySectionStatusDialog').load(win)
	CrashHandler = require('../crashHandler').load(win)
	ExpandingTextArea = require('../expandingTextArea').load(win)
	WithTooltip = require('../withTooltip').load(win)
	MetricLookupField = require('../metricLookupField').load(win)
	MetricWidget = require('../metricWidget').load(win)
	OpenDialogLink = require('../openDialogLink').load(win)
	PrintButton = require('../printButton').load(win)

	{
		FaIcon, renderLineBreaks, showWhen, stripMetadata, formatTimestamp, capitalize
	} = require('../utils').load(win)

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
			planChanged = not Imm.is(newProps.plan, @props.plan)
			planTargetsChanged = not Imm.is(newProps.planTargetsById, @props.planTargetsById)

			if planChanged or planTargetsChanged
				@setState {
					plan: newProps.plan
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

			hasChanges = @hasChanges()

			return R.div({className: "planView"},
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
						R.div({className: 'leftMenu'},
							R.button({
								className: [
									'btn'
									if hasChanges then 'btn-success'
									'saveButton'
								].join ' '
								disabled: not hasChanges or @props.isReadOnly
								onClick: @_save
							},
								FaIcon('save')
								"Save #{Term 'Plan'}"
							)
							R.button({
								className: "btn btn-link #{showWhen hasChanges}"
								onClick: @_resetChanges
							},
								"Discard Changes"
							)
						)
						R.div({className: 'rightMenu'},
							R.div({className: 'btn-group btn-group'},
								R.button({
									className: 'addSection btn btn-default'
									onClick: @_addSection
									disabled: hasChanges or @props.isReadOnly
								},
									FaIcon('plus')
									"Add #{Term 'section'}"
								)
							)
							WithTooltip({
								placement: 'bottom'
								title: "Create plan template"
							},
								R.button({
									className: 'btn createTemplateButton'
									onClick: @_createTemplate
								},
									FaIcon('wpforms')
								)
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
								disabled: hasChanges or @props.isReadOnly
								tooltip: {
									show: true
									placement: 'bottom'
									title: (
										if hasChanges or @props.isReadOnly
											"Please save the changes to #{Term 'client'}'s #{Term 'plan'} before printing"
										else
											"Print plan"
									)
								}
							})
						)
					)
					SectionsView({
						clientFile: @props.clientFile
						plan: @state.plan
						metricsById: @props.metricsById
						currentTargetRevisionsById: @state.currentTargetRevisionsById
						selectedTargetId: @state.selectedTargetId
						isReadOnly: @props.isReadOnly
						planTargetsById: @props.planTargetsById

						renameSection: @_renameSection
						addTargetToSection: @_addTargetToSection
						removeNewTarget: @_removeNewTarget
						removeNewSection: @_removeNewSection
						hasTargetChanged: @_hasTargetChanged
						updateTarget: @_updateTarget
						setSelectedTarget: @_setSelectedTarget
						addMetricToTarget: @_addMetricToTarget
						deleteMetricFromTarget: @_deleteMetricFromTarget
						getSectionIndex: @_getSectionIndex
					})
				)
				R.div({className: 'targetDetail'},
					(if not selectedTarget?
						R.div({className: "noSelection #{showWhen plan.get('sections').size > 0}"},
							"More information will appear here when you select ",
							"a #{Term 'target'} on the left."
						)
					else
						R.div({className: 'targetDetailContainer'},
							RevisionHistory({
								revisions: selectedTarget.get('revisions')
								type: 'planTarget'
								metricsById: @props.metricsById
								programsById: @props.programsById
								dataModelName: 'target'
								terms: {
									metric: Term 'metric'
								}
							})
						)
					)
				)
			)

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

		_resetChanges: ->
			Bootbox.confirm "Discard all changes made to the #{Term 'plan'}?", (ok) =>
				if ok
					@setState {
						currentTargetRevisionsById: @_generateCurrentTargetRevisionsById @props.planTargetsById
						plan: @props.plan
					}

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
						status: 'default'
					}

				@setState {plan: newPlan}, =>
					@_addTargetToSection sectionId

		_createTemplate: ->
			Bootbox.prompt "Enter a name for the new Template:", (templateName) =>
				unless templateName
					return

				templateSections = @state.plan.get('sections').map (section) =>
					sectionTargets = section.get('targetIds').map (targetId) =>
						target = @state.currentTargetRevisionsById.get(targetId)
						# Removing irrelevant data from object
						return target
						.remove('status')
						.remove('statusReason')
						.remove('clientFileId')
						.remove('id')

					section = Imm.fromJS {
						name: section.get('name')
						targets: sectionTargets
					}

				planTemplate = Imm.fromJS {
					name: templateName
					status: 'default'
					sections: templateSections
				}

				global.ActiveSession.persist.planTemplates.create planTemplate, (err, obj) =>
					if err instanceof Persist.IOError
						console.error err
						Bootbox.alert """
							Please check your network connection and try again
						"""
						return
					Bootbox.alert "New template: '#{templateName}' created."

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

		_removeNewTarget: (sectionId, transientTargetId) ->
			sectionIndex = @_getSectionIndex sectionId

			plan = @state.plan.updateIn ['sections', sectionIndex, 'targetIds'], (targetIds) =>
				targetIndex = targetIds.indexOf transientTargetId
				return targetIds.splice(targetIndex, 1)

			currentTargetRevisionsById = @state.currentTargetRevisionsById.delete transientTargetId

			@setState {plan, currentTargetRevisionsById}

		_removeNewSection: (section) ->
			sectionId = section.get('id')
			sectionIndex = @_getSectionIndex sectionId

			# Update plan
			plan = @state.plan.set 'sections', @state.plan.get('sections').splice(sectionIndex, 1)

			# Filter out all this section's targetIds from currentTargetRevisionsById
			currentTargetRevisionsById = @state.currentTargetRevisionsById.filterNot (targetRevision, targetId) ->
				section.get('targetIds').contains targetId

			@setState {plan, currentTargetRevisionsById}

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
				displayDeactivatedSections: null
				displayCompletedSections: null
			}

		componentDidMount: ->
			sectionsDom = @refs.sections
			sectionsDom.addEventListener 'scroll', (event) =>
				@_recalculateOffsets()

		render: ->
			{
				clientFile
				plan
				metricsById
				currentTargetRevisionsById
				planTargetsById
				selectedTargetId
				isReadOnly

				renameSection
				addTargetToSection
				hasTargetChanged
				updateTarget
				removeNewTarget
				removeNewSection
				setSelectedTarget
				addMetricToTarget
				deleteMetricFromTarget
				getSectionIndex
			} = @props


			# Group sections into an object, with a property for each status
			sectionsByStatus = plan.get('sections').groupBy (section) ->
				return section.get('status')

			return R.div({className: 'sections', ref: 'sections'},
				(if sectionsByStatus.has('default')

					# Default status
					(sectionsByStatus.get('default').map (section) =>
						SectionView({
							key: section.get('id')
							ref: 'section-' + section.get('id')

							section
							clientFile
							plan
							metricsById
							currentTargetRevisionsById
							planTargetsById
							selectedTargetId
							isReadOnly

							renameSection
							addTargetToSection
							hasTargetChanged
							updateTarget
							removeNewTarget
							setSelectedTarget
							addMetricToTarget
							deleteMetricFromTarget
							getSectionIndex
							onRemoveNewSection: removeNewSection.bind null, section

							sectionOffsets: @state.sectionOffsets
							sectionsScrollTop: @state.sectionsScrollTop
						})
					)
				)
				(if sectionsByStatus.has('completed')
					R.div({className: 'sections status-completed'},
						R.span({
							className: 'inactiveSectionHeader'
							onClick: @_toggleDisplayCompletedSections
						},
							# Rotates 90'CW when expanded
							FaIcon('caret-right', {
								className: 'expanded' if @state.displayCompletedSections
							})
							R.strong({}, sectionsByStatus.get('completed').size)
							" Completed "
							Term (
								if sectionsByStatus.get('completed').size > 1 then 'Sections' else 'Section'
							)
						)
						(if @state.displayCompletedSections
							# Completed status
							(sectionsByStatus.get('completed').map (section) =>
								SectionView({
									key: section.get('id')
									ref: 'section-' + section.get('id')

									section
									clientFile
									plan
									metricsById
									currentTargetRevisionsById
									planTargetsById
									selectedTargetId
									isReadOnly

									renameSection
									addTargetToSection
									hasTargetChanged
									updateTarget
									removeNewTarget
									removeNewSection
									onRemoveNewSection: removeNewSection.bind null, section
									setSelectedTarget
									addMetricToTarget
									deleteMetricFromTarget
									getSectionIndex

									sectionOffsets: @state.sectionOffsets
									sectionsScrollTop: @state.sectionsScrollTop
								})
							)
						)
					)
				)
				(if sectionsByStatus.has('deactivated')
					R.div({className: 'sections status-deactivated'},
						R.span({
							className: 'inactiveSectionHeader'
							onClick: @_toggleDisplayDeactivatedSections
						},
							# Rotates 90'CW when expanded
							FaIcon('caret-right', {
								className: 'expanded' if @state.displayDeactivatedSections
							})
							R.strong({}, sectionsByStatus.get('deactivated').size)
							" Deactivated "
							Term (
								if sectionsByStatus.get('deactivated').size > 1 then 'Sections' else 'Section'
							)
						)
						(if @state.displayDeactivatedSections
							# Deactivated status
							(sectionsByStatus.get('deactivated').map (section) =>
								SectionView({
									key: section.get('id')
									ref: 'section-' + section.get('id')

									section
									clientFile
									plan
									metricsById
									currentTargetRevisionsById
									planTargetsById
									selectedTargetId
									isReadOnly

									renameSection
									addTargetToSection
									hasTargetChanged
									updateTarget
									removeNewTarget
									removeNewSection
									onRemoveNewSection: removeNewSection.bind null, section
									setSelectedTarget
									addMetricToTarget
									deleteMetricFromTarget
									getSectionIndex

									sectionOffsets: @state.sectionOffsets
									sectionsScrollTop: @state.sectionsScrollTop
								})
							)
						)
					)
				)
			)

		_recalculateOffsets: ->
			sectionsDom = @refs.sections
			sectionsScrollTop = sectionsDom.scrollTop

			sectionOffsets = @props.plan.get('sections').flatMap (section) =>
				ref = @refs['section-' + section.get('id')]

				# Some [inactive] sections may be hidden from DOM, so no refs
				return [] unless ref?

				sectionDom = ReactDOM.findDOMNode(ref)

				offset = Imm.Map({
					top: sectionDom.offsetTop
					height: sectionDom.offsetHeight
				})

				return [[section.get('id'), offset]]
			.fromEntrySeq().toMap()

			@setState (s) -> {sectionsScrollTop, sectionOffsets}

		_toggleDisplayDeactivatedSections: ->
			displayDeactivatedSections = not @state.displayDeactivatedSections
			@setState {displayDeactivatedSections}

		_toggleDisplayCompletedSections: ->
			displayCompletedSections = not @state.displayCompletedSections
			@setState {displayCompletedSections}


	SectionView = React.createFactory React.createClass
		displayName: 'SectionView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				displayCancelledTargets: null
				displayCompletedTargets: null
			}

		render: ->
			{
				section
				clientFile
				plan
				metricsById
				currentTargetRevisionsById
				planTargetsById
				selectedTargetId
				isReadOnly

				renameSection
				addTargetToSection
				hasTargetChanged
				updateTarget
				removeNewTarget
				removeNewSection
				onRemoveNewSection
				setSelectedTarget
				addMetricToTarget
				deleteMetricFromTarget
				getSectionIndex
			} = @props

			sectionId = section.get('id')
			headerState = 'inline'

			# Group targetIds into an object, with a property for each status
			targetIdsByStatus = section.get('targetIds').groupBy (targetId) ->
				return currentTargetRevisionsById.getIn([targetId, 'status'])

			# Recalculate sticky header
			if @props.sectionOffsets and @props.sectionOffsets.get(section.get('id'))
				scrollTop = @props.sectionsScrollTop
				sectionOffset = @props.sectionOffsets.get(section.get('id'))

				headerHeight = 60
				minSticky = sectionOffset.get('top')
				maxSticky = sectionOffset.get('top') + sectionOffset.get('height') - headerHeight

				if scrollTop >= minSticky and scrollTop < maxSticky
					headerState = 'sticky'

			return R.div({
				className: "section status-#{section.get('status')}"
				key: section.get('id')
			},
				SectionHeader({
					clientFile
					type: 'inline'
					visible: headerState is 'inline'
					section
					isReadOnly
					renameSection
					getSectionIndex
					addTargetToSection
					onRemoveNewSection
					targetIdsByStatus
				})
				SectionHeader({
					clientFile
					type: 'sticky'
					visible: headerState is 'sticky'
					scrollTop: @props.sectionsScrollTop
					section
					isReadOnly
					renameSection
					getSectionIndex
					addTargetToSection
					onRemoveNewSection
					targetIdsByStatus # TODO is this faster as a prop or to recalculate from section?
				})
				(if section.get('targetIds').size is 0
					R.div({className: 'noTargets'},
						"This #{Term 'section'} is empty."
					)
				)

				# TODO: Generalize these 3 into a single component

				(if targetIdsByStatus.has('default')
					R.div({className: 'targets status-default'},
						# Default status
						(targetIdsByStatus.get('default').map (targetId) =>
							PlanTarget({
								currentRevision: currentTargetRevisionsById.get targetId
								metricsById
								hasTargetChanged: hasTargetChanged targetId
								key: targetId
								isActive: targetId is selectedTargetId
								isExistingTarget: planTargetsById.has(targetId)
								isReadOnly
								onRemoveNewTarget: removeNewTarget.bind null, sectionId, targetId
								onTargetUpdate: updateTarget.bind null, targetId
								onTargetSelection: setSelectedTarget.bind null, targetId
								addMetricToTarget
								deleteMetricFromTarget
								targetId
							})
						)
					)
				)
				(if targetIdsByStatus.has('completed')
					R.div({className: 'targets status-completed'},
						R.span({
							className: 'inactiveTargetHeader'
							onClick: @_toggleDisplayCompletedTargets
						},
							# Rotates 90'CW when expanded
							FaIcon('caret-right', {
								className: 'expanded' if @state.displayCompletedTargets
							})
							R.strong({}, targetIdsByStatus.get('completed').size)
							" Completed "
							Term (
								if targetIdsByStatus.get('completed').size > 1 then 'Targets' else 'Target'
							)
						)
						(if @state.displayCompletedTargets
							# Completed status
							(targetIdsByStatus.get('completed').map (targetId) =>
								PlanTarget({
									currentRevision: currentTargetRevisionsById.get targetId
									metricsById
									hasTargetChanged: hasTargetChanged targetId
									key: targetId
									isActive: targetId is selectedTargetId
									isExistingTarget: planTargetsById.has(targetId)
									isReadOnly
									isInactive: true
									onRemoveNewTarget: removeNewTarget.bind null, sectionId, targetId
									onTargetUpdate: updateTarget.bind null, targetId
									onTargetSelection: setSelectedTarget.bind null, targetId
									addMetricToTarget
									deleteMetricFromTarget
									targetId
								})
							)
						)
					)
				)
				(if targetIdsByStatus.has('deactivated')
					R.div({className: 'targets status-deactivated'},
						R.span({
							className: 'inactiveTargetHeader'
							onClick: @_toggleDisplayCancelledTargets
						},
							# Rotates 90'CW when expanded
							FaIcon('caret-right', {
								className: 'expanded' if @state.displayCancelledTargets
							})
							R.strong({}, targetIdsByStatus.get('deactivated').size)
							" Deactivated "
							Term (
								if targetIdsByStatus.get('deactivated').size > 1 then 'Targets' else 'Target'
							)
						)
						(if @state.displayCancelledTargets
							# Cancelled statuses
							(targetIdsByStatus.get('deactivated').map (targetId) =>
								PlanTarget({
									currentRevision: currentTargetRevisionsById.get targetId
									metricsById
									hasTargetChanged: hasTargetChanged targetId
									key: targetId
									isActive: targetId is selectedTargetId
									isExistingTarget: planTargetsById.has(targetId)
									isReadOnly
									isInactive: true
									onRemoveNewTarget: removeNewTarget.bind null, sectionId, targetId
									onTargetUpdate: updateTarget.bind null, targetId
									onTargetSelection: setSelectedTarget.bind null, targetId
									addMetricToTarget
									deleteMetricFromTarget
									targetId
								})
							)
						)
					)
				)
			)

		_toggleDisplayCancelledTargets: ->
			displayCancelledTargets = not @state.displayCancelledTargets
			@setState {displayCancelledTargets}

		_toggleDisplayCompletedTargets: ->
			displayCompletedTargets = not @state.displayCompletedTargets
			@setState {displayCompletedTargets}


	SectionHeader = React.createFactory React.createClass
		displayName: 'SectionHeader'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			sectionStatus = @props.section.get('status')
			{
				clientFile
				type
				visible
				scrollTop
				section
				isReadOnly
				renameSection
				getSectionIndex
				addTargetToSection
				removeNewSection
				onRemoveNewSection
			} = @props

			# Figure out whether already exists in plan
			isExistingSection = clientFile.getIn(['plan','sections'])
			.some (obj) => obj.get('id') is section.get('id')

			sectionIsInactive = section.get('status') isnt 'default'

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
						disabled: isReadOnly or sectionIsInactive
					},
						"Rename"
					)
					R.button({
						className: 'addTarget btn btn-primary'
						onClick: addTargetToSection.bind null, section.get('id')
						disabled: isReadOnly or sectionIsInactive
					},
						FaIcon('plus')
						"Add #{Term 'target'}"
					)
				)
				(if isExistingSection
					unless @props.targetIdsByStatus.has('default')
						if sectionStatus is 'default'
							R.div({className: 'statusButtonGroup'},
								WithTooltip({title: "Deactivate #{Term 'Section'}", placement: 'top', container: 'body'},
									OpenDialogLink({
										clientFile
										className: 'statusButton'
										dialog: ModifySectionStatusDialog
										newStatus: 'deactivated'
										sectionIndex: getSectionIndex section.get('id')
										# sectionTargetIds: section.get('targetIds')
										title: "Deactivate #{Term 'Section'}"
										message: """
											This will remove the #{Term 'section'} from the #{Term 'client'}
											#{Term 'plan'}, and future #{Term 'progress notes'}.
											It may be re-activated again later.
										"""
										reasonLabel: "Reason for deactivation:"
										disabled: @props.isReadOnly or @props.hasTargetChanged
									},
										FaIcon 'times'
									)
								)
								WithTooltip({title: "Complete #{Term 'Section'}", placement: 'top', container: 'body'},
									OpenDialogLink({
										clientFile
										className: 'statusButton'
										dialog: ModifySectionStatusDialog
										newStatus: 'completed'
										sectionIndex: getSectionIndex section.get('id')
										# sectionTargetIds: section.get('targetIds')
										title: "Complete #{Term 'Section'}"
										message: """
											This will set the #{Term 'section'} as 'completed'. This often
											means that the desired outcome has been reached.
										"""
										reasonLabel: "Reason for completion:"
										disabled: @props.isReadOnly or @props.hasTargetChanged
									},
										FaIcon 'check'
									)
								)
							)
						else
							R.div({className: 'statusButtonGroup'},
								WithTooltip({title: "Reactivate #{Term 'Section'}", placement: 'top', container: 'body'},
									OpenDialogLink({
										clientFile
										className: 'statusButton'
										dialog: ModifySectionStatusDialog
										newStatus: 'default'
										sectionIndex: getSectionIndex section.get('id')
										# sectionTargetIds: section.get('targetIds')
										title: "Reactivate #{Term 'Section'}"
										message: """
											This will reactivate the #{Term 'section'} so it appears in the #{Term 'client'}
											#{Term 'plan'}, and future #{Term 'progress notes'}.
										"""
										reasonLabel: "Reason for reactivation:"
										disabled: @props.isReadOnly or @props.hasTargetChanged
									},
										FaIcon 'sign-in'
									)
								)
							)
				else
					R.div({className: 'statusButtonGroup'},
						R.div({
							className: 'statusButton'
							onClick: onRemoveNewSection
						},
							FaIcon 'times'
						)
					)
				)

			)


	PlanTarget = React.createFactory React.createClass
		displayName: 'PlanTarget'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			currentRevision = @props.currentRevision
			revisionStatus = @props.currentRevision.get('status')

			return R.div({
				className: [
					'target'
					"target-#{currentRevision.get('id')}"
					"status-#{revisionStatus}"
					'active' if @props.isActive
					'hasChanges' if @props.hasTargetChanged or not @props.isExistingTarget
					'readOnly' if @props.isReadOnly
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
						disabled: @props.isReadOnly or @props.isInactive
						onChange: @_updateField.bind null, 'name'
						onFocus: @props.onTargetSelection unless @props.isReadOnly or @props.isInactive
						onClick: @props.onTargetSelection if @props.isReadOnly or @props.isInactive

					})

					(if @props.isExistingTarget
						# Can cancel/complete a 'default' target
						(if revisionStatus is 'default'
							R.div({className: 'statusButtonGroup'},
								WithTooltip({title: "Deactivate #{Term 'Target'}", placement: 'top'},
									OpenDialogLink({
										className: 'statusButton'
										dialog: ModifyTargetStatusDialog
										planTarget: @props.currentRevision
										newStatus: 'deactivated'
										title: "Deactivate #{Term 'Target'}"
										message: """
											This will remove the #{Term 'target'} from the #{Term 'client'}
											#{Term 'plan'}, and future #{Term 'progress notes'}.
											It may be re-activated again later.
										"""
										reasonLabel: "Reason for deactivation:"
										disabled: @props.isReadOnly or @props.hasTargetChanged
									},
										FaIcon 'times'
									)
								)
								WithTooltip({title: "Complete #{Term 'Target'}", placement: 'top'},
									OpenDialogLink({
										className: 'statusButton'
										dialog: ModifyTargetStatusDialog
										planTarget: @props.currentRevision
										newStatus: 'completed'
										title: "Complete #{Term 'Target'}"
										message: """
											This will set the #{Term 'target'} as 'completed'. This often
											means that the desired outcome has been reached.
										"""
										reasonLabel: "Reason for completion:"
										disabled: @props.isReadOnly or @props.hasTargetChanged
									},
										FaIcon 'check'
									)
								)
							)
						else
							R.div({className: 'statusButtonGroup'},
								WithTooltip({title: "Re-Activate #{Term 'Target'}", placement: 'top'},
									OpenDialogLink({
										className: 'statusButton'
										dialog: ModifyTargetStatusDialog
										planTarget: @props.currentRevision
										newStatus: 'default'
										title: "Re-Activate #{Term 'Target'}"
										message: """
											This will re-activate the #{Term 'target'}, so it appears
											in the #{Term 'client'} #{Term 'plan'} and
											future #{Term 'progress notes'}.
										"""
										reasonLabel: "Reason for activation:"
										disabled: @props.isReadOnly
									},
										FaIcon 'sign-in'
									)
								)
							)
						)
					else
						R.div({className: 'statusButtonGroup'},
							R.div({
								className: 'statusButton'
								onClick: @props.onRemoveNewTarget
								title: 'Cancel'
							},
								FaIcon 'times'
							)
						)
					)
				)

				R.div({className: 'descriptionContainer'},
					ExpandingTextArea({
						className: 'description field'
						ref: 'descriptionField'
						placeholder: "Describe the current #{Term 'treatment plan'} . . ."
						value: currentRevision.get('description')
						disabled: @props.isReadOnly or @props.isInactive
						onChange: @_updateField.bind null, 'description'
						onFocus: @props.onTargetSelection unless @props.isReadOnly or @props.isInactive
						onClick: @props.onTargetSelection if @props.isReadOnly or @props.isInactive
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
							tooltipViewport: '.section'
							isEditable: false
							allowDeleting: not @props.isReadOnly and @props.isActive and not @props.isInactive
							onDelete: @props.deleteMetricFromTarget.bind(
								null, @props.targetId, metricId
							)
						})
					).toJS()...
					(if not @props.isReadOnly and not @props.isInactive
						R.button({
							className: "btn btn-link addMetricButton #{showWhen @props.isActive}"
							onClick: @_focusMetricLookupField.bind(null, @props.targetId)
						},
							FaIcon('plus')
							" Add #{Term 'metric'}"
						)
					)
				)
				(if not @props.isReadOnly and not @props.isInactive
					R.div({
						className: [
							'metricLookupContainer'
						].join ' '
						ref: 'metricLookup'
					},
						MetricLookupField({
							metrics: @props.metricsById.valueSeq()
							onSelection: @props.addMetricToTarget.bind(
								null, @props.targetId
							)
							placeholder: "Find / Define a #{Term 'Metric'}"
							isReadOnly: @props.isReadOnly
							onBlur: @_hideMetricInput
						})
					)
				)
			)

		_updateField: (fieldName, event) ->
			newValue = @props.currentRevision.set fieldName, event.target.value
			@props.onTargetUpdate newValue


		_onTargetClick: (event) ->
			unless (event.target.classList.contains 'field') or (event.target.classList.contains 'lookupField') or (event.target.classList.contains 'btn')
				@refs.nameField.focus() unless @props.isReadOnly
				@props.onTargetSelection()

		_focusMetricLookupField: ->
			$(@refs.metricLookup).show()
			$('.lookupField').focus()

		_hideMetricInput: ->
			$(@refs.metricLookup).hide()

	return {PlanView}

module.exports = {load}
