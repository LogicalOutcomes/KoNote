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
	{findDOMNode} = ReactDOM
	B = require('../utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')

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
	ReorderPlanView = require('./reorderPlanView').load(win)
	CreatePlanTemplateDialog = require('./createPlanTemplateDialog').load(win)

	{
		FaIcon, renderLineBreaks, showWhen, stripMetadata,
		formatTimestamp, capitalize, scrollToElement
	} = require('../utils').load(win)


	PlanView = React.createFactory React.createClass
		displayName: 'PlanView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {
				plan: @props.plan
				currentTargetRevisionsById: @_generateCurrentTargetRevisionsById @props.planTargetsById

				selectedTargetId: null
				isReorderingPlan: null
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

				OpenDialogLink({
					ref: 'test'
					className: ''
					dialog: CreatePlanTemplateDialog
					title: "Create Template from Plan"
					sections: @state.plan.get('sections')
					currentTargetRevisionsById: @state.currentTargetRevisionsById
					# disabled: isReadOnly
				})

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
						R.span({className: 'templates'},
							(unless @props.planTemplateHeaders.isEmpty()
								B.DropdownButton({
									className: 'btn btn-lg'
									title: "Apply #{Term 'Template'}"
									disabled: @props.isReadOnly
								},
									(@props.planTemplateHeaders.map (planTemplateHeader) =>
										B.MenuItem({
											key: planTemplateHeader.get('id')
											onClick: @_applyPlanTemplate.bind null, planTemplateHeader.get('id')
										},
											planTemplateHeader.get('name')
										)
									)
								)
							)
						)
					)
					R.div({className: "flexButtonToolbar #{showWhen plan.get('sections').size > 0}"},
						R.button({
							className: [
								'saveButton'
								#'collapsed' unless hasChanges
							].join ' '
							disabled: @props.isReadOnly or not hasChanges
							onClick: @_save
						},
							FaIcon('save', {className:'menuItemIcon'})
							R.span({className: 'menuItemText'},
								"Save"
							)
						)

						R.button({
							className: [
								'discardButton'
								#'collapsed' unless hasChanges
							].join ' '
							disabled: @props.isReadOnly or not hasChanges
							onClick: @_resetChanges
						},
							FaIcon('undo', {className:'menuItemIcon'})
							R.span({className: 'menuItemText'},
								"Discard"
							)
						)

						PrintButton({
							#className: 'collapsed' if hasChanges
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
							iconOnly: false
							iconClassName: 'menuItemIcon'
							labelClassName: 'menuItemText'
							disabled: hasChanges
						})

						B.DropdownButton({
							id: 'planTemplatesDropdown'
							key: 'planTemplatesDropdownButton'
							title: R.span({},
								FaIcon('wpforms', {className:'menuItemIcon'})
								R.span({className: 'menuItemText'},
									"Templates"
								)
							)
							disabled: @props.isReadOnly
							noCaret: true
						},

							B.MenuItem({onClick: @_openCreateTemplateDialog},
								"Create Plan Template"
							)


							(unless @props.planTemplateHeaders.isEmpty()
								[
									B.MenuItem({divider: true})

									B.MenuItem({header: true}, R.h5({}, "Apply #{Term 'Template'}"))

									(@props.planTemplateHeaders.map (planTemplateHeader) =>
										B.MenuItem({
											key: planTemplateHeader.get('id')
											onClick: @_applyPlanTemplate.bind null, planTemplateHeader.get('id')
											disabled: @props.isReadOnly
										},
											planTemplateHeader.get('name')
										)
									)
								]
							)
						)

						R.button({
							className: 'reorderButton'
							onClick: => @_toggleReorderPlan()
							disabled: @props.isReadOnly
						},
							(if @state.isReorderingPlan
								R.div({},
									FaIcon('sitemap', {className:'menuItemIcon'})
									R.span({className: 'menuItemText'},
										"Edit Plan"
									)
								)
							else
								R.div({},
									FaIcon('sort-amount-asc', {className:'menuItemIcon'})
									R.span({className: 'menuItemText'},
										"Reorder"
									)
								)
							)
						)

						R.button({
							className: 'addSectionButton'
							onClick: @_addSection
							disabled: @props.isReadOnly
						},
							FaIcon('plus', {className:'menuItemIcon'})
							R.span({className: 'menuItemText'},
								"#{Term 'Section'}"
							)
						)

					)

					SectionsView({
						ref: 'sectionsView'
						isVisible: not @state.isReorderingPlan
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

					ReorderPlanView({
						isVisible: @state.isReorderingPlan
						plan: @state.plan
						currentTargetRevisionsById: @state.currentTargetRevisionsById
						reorderSection: @_reorderSection
						reorderTargetId: @_reorderTargetId
						toggleReorderPlan: @_toggleReorderPlan
						scrollToSection: @_scrollToSection
						scrollToTarget: @_scrollToTarget
					})

				)

				R.div({className: 'targetDetail'},
					(if not selectedTarget?
						R.div({className: "noSelection #{showWhen plan.get('sections').size > 0}"},
							"More information will appear here when you select ",
							"a #{Term 'target'} on the left."
						)
					else
						R.div({className: 'revisionHistoryContainer'},
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

		_hasTargetChanged: (targetId, currentTargetRevisionsById, planTargetsById) ->
			# Default to retrieving these values from the component
			currentTargetRevisionsById or= @state.currentTargetRevisionsById
			planTargetsById or= @props.planTargetsById

			# Get current revision (normalized) of the specified target
			currentRev = @_normalizeTarget currentTargetRevisionsById.get(targetId)

			# If this is a new target
			target = planTargetsById.get(targetId, null)
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

				# Capture these values for use in filtering functions below.
				# This is necessary to ensure that they won't change between
				# now and when the filtering functions are actually called.
				currentTargetRevisionsById = @state.currentTargetRevisionsById
				planTargetsById = @props.planTargetsById

				newPlanTargets = currentTargetRevisionsById.valueSeq()
				.filter (target) =>
					# Only include targets that have not been saved yet
					return not planTargetsById.has(target.get('id'))
				.map(@_normalizeTarget)

				updatedPlanTargets = currentTargetRevisionsById.valueSeq()
				.filter (target) =>
					# Ignore new targets
					unless planTargetsById.has(target.get('id'))
						return false

					# Only include targets that have actually changed
					return @_hasTargetChanged(
						target.get('id'),
						currentTargetRevisionsById,
						planTargetsById
					)
				.map(@_normalizeTarget)

				@props.updatePlan @state.plan, newPlanTargets, updatedPlanTargets

		_toggleReorderPlan: (cb=(->)) ->
			isReorderingPlan = not @state.isReorderingPlan
			@setState {isReorderingPlan}, cb

		_reorderSection: (dragIndex, hoverIndex) ->
			if @props.isReadOnly
				@_showReadOnlyAlert()
				return

			sections = @state.plan.get('sections')
			dragSection = sections.get(dragIndex)

			sections = sections
			.delete(dragIndex)
			.splice(hoverIndex, 0, dragSection)

			plan = @state.plan.set('sections', sections)

			@setState {plan}

		_reorderTargetId: (sectionIndex, dragIndex, hoverIndex) ->
			if @props.isReadOnly
				@_showReadOnlyAlert()
				return

			targetIds = @state.plan.getIn(['sections', sectionIndex, 'targetIds'])
			dragTarget = targetIds.get(dragIndex)

			targetIds = targetIds
			.delete(dragIndex)
			.splice(hoverIndex, 0, dragTarget)

			plan = @state.plan.setIn(['sections', sectionIndex, 'targetIds'], targetIds)

			@setState {plan}

		_showReadOnlyAlert: ->
			Bootbox.alert "Sorry, you can't modify the #{Term 'plan'} while in read-only mode."

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

		_openCreateTemplateDialog: (event) ->
			@refs.test.open(event)

		_applyPlanTemplate: (templateId) ->
			Bootbox.confirm "Are you sure you want to apply this template?", (ok) =>
				if ok
					clientFileHeaders = null
					selectedPlanTemplate = null
					templateSections = null
					existsElsewhere = null
					newCurrentRevs = null
					newPlan = null
					targetIds = Imm.List()
					clientFileId = @props.clientFileId

					Async.series [

						(cb) =>
							ActiveSession.persist.planTemplates.readLatestRevisions templateId, 1, (err, result) ->
								if err
									cb err
									return

								selectedPlanTemplate = stripMetadata result.get(0)
								cb()

						(cb) =>
							newCurrentRevs = @state.currentTargetRevisionsById
							templateSections = selectedPlanTemplate.get('sections').map (templateSection) =>
								targetIds = Imm.List()
								templateSection.get('targets').forEach (target) =>
									target.get('metricIds').forEach (metricId) =>

										# Metric exists in another target
										existsElsewhere = @state.currentTargetRevisionsById.some (target) =>
											return target.get('metricIds').contains(metricId)
										if existsElsewhere
											return

									targetId = '__transient__' + Persist.generateId()
									targetIds = targetIds.push targetId

									newTarget = Imm.fromJS {
										id: targetId
										clientFileId
										name: target.get('name')
										description: target.get('description')
										status: 'default'
										metricIds: target.get('metricIds')
									}

									newCurrentRevs = newCurrentRevs.set targetId, newTarget

								section = templateSection.set 'status', 'default'
								.set 'targetIds', targetIds
								.set 'id', Persist.generateId()
								.remove 'targets'

								return section

							if existsElsewhere
								cb('CANCEL')
								return
							cb()

						(cb) =>

							newPlan = @state.plan.update 'sections', (sections) =>
								return sections.concat(templateSections)

							@setState {
								plan: newPlan
								currentTargetRevisionsById: newCurrentRevs
							}

							cb()

					], (err) =>
						if err
							if err is 'CANCEL'
								Bootbox.alert "A #{Term 'metric'} in this template already exists for another #{Term 'plan target'}"
								return

							if err instanceof Persist.IOError
								console.error err
								Bootbox.alert """
									Please check your network connection and try again.
								"""
								return

							CrashHandler.handle err
							return
					return

		_renameSection: (sectionId) ->
			sectionIndex = @_getSectionIndex sectionId
			sectionName = @state.plan.getIn ['sections', sectionIndex, 'name']

			Bootbox.prompt {
				title: "Rename #{Term 'section'}:"
				value: sectionName
				callback: (newSectionName) =>
					newSectionName = newSectionName?.trim()

					unless newSectionName
						return

					newPlan = @state.plan.setIn ['sections', sectionIndex, 'name'], newSectionName
					@setState {plan: newPlan}
			}

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

		_addMetricToTarget: (targetId, cb, metricId) ->
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
			}, cb

		_deleteMetricFromTarget: (targetId, metricId) ->
			@setState {
				currentTargetRevisionsById: @state.currentTargetRevisionsById.update targetId, (currentRev) ->
					return currentRev.update 'metricIds', (metricIds) ->
						return metricIds.filter (id) ->
							return id isnt metricId
			}

		_scrollToSection: (section) ->
			{id, status} = section.toObject()
			sectionElementId = "section-#{id}"

			# Ensure this sectionHeader replaces the sticky one above it
			stickyHeaderOffset = $('.sectionName').height() * -1
			$sectionName = $("##{sectionElementId} .sectionName")

			Async.series [
				(cb) => @setState {isReorderingPlan: false}, cb
				(cb) => @refs.sectionsView.expandSection section, cb
				(cb) =>
					@_scrollTo sectionElementId, stickyHeaderOffset, cb
					# Highlight the destination
					$sectionName.addClass 'highlight'
			], (err) =>
				if err
					CrashHandler.handle err
					return

				# Remove highlight after 1s
				setTimeout (=> $sectionName.removeClass 'highlight'), 1000

				# Done scrolling to section

		_scrollToTarget: (target, section) ->
			{id, status} = target.toObject()
			targetElementId = "target-#{id}"

			# Switch views & select target, expand groups if needed, scroll
			Async.series [
				(cb) => @setState {isReorderingPlan: false, selectedTargetId: id}, cb
				(cb) => @refs.sectionsView.expandTarget target, section, cb
				(cb) => @_scrollTo targetElementId, 0, cb
			], (err) =>
				if err
					CrashHandler.handle err
					return

				# Done scrolling and target selection

		_scrollTo: (elementId, additionalOffset, cb=(->)) ->
			$container = findDOMNode(@refs.sectionsView)
			$element = win.document.getElementById(elementId)

			topOffset = 25 + additionalOffset # Add offset depending on top padding
			scrollToElement $container, $element, 1000, 'easeInOutQuad', topOffset, cb


	SectionsView = React.createFactory React.createClass
		displayName: 'SectionsView'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		getInitialState: -> {
			displayDeactivatedSections: null
			displayCompletedSections: null
		}

		getDefaultProps: -> {
			isVisible: true
		}

		expandSection: (section, cb) ->
			{status, id} = section.toObject()

			switch status
				when 'default'
					cb()
				when 'completed'
					@_toggleDisplayCompletedSections(true, cb)
				when 'deactivated'
					@_toggleDisplayDeactivatedSections(true, cb)
				else
					throw new Error "Unknown status: #{status}"

		expandTarget: (target, section, cb) ->
			sectionId = section.get('id')
			status = target.get('status')
			# First ensure the section is available
			@expandSection section, =>
				# Ask it to expand completed/deactivated targets
				@refs["section-#{sectionId}"].expandTargetsWithStatus status, cb

		render: ->
			{
				clientFile
				plan
				metricsById
				currentTargetRevisionsById
				planTargetsById
				selectedTargetId
				isReadOnly
				isVisible

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


			sectionsByStatus = plan.get('sections').groupBy (s) -> s.get('status')

			activeSections = sectionsByStatus.get('default')
			completedSections = sectionsByStatus.get('completed')
			deactivatedSections = sectionsByStatus.get('deactivated')


			return R.div({className: "sections #{showWhen isVisible}"},

				(activeSections.map (section) =>
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
					})
				)

				(if completedSections
					R.div({className: 'sections status-completed'},
						R.span({
							className: 'inactiveSectionHeader'
							onClick: => @_toggleDisplayCompletedSections()
						},
							# Rotates 90'CW when expanded
							FaIcon('caret-right', {
								className: 'expanded' if @state.displayCompletedSections
							})
							R.strong({}, completedSections.size)
							" Completed "
							Term (
								if completedSections.size > 1 then 'Sections' else 'Section'
							)
						)

						(if @state.displayCompletedSections
							# Completed status
							(completedSections.map (section) =>
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
								})
							)
						)
					)
				)

				(if deactivatedSections
					R.div({className: 'sections status-deactivated'},
						R.span({
							className: 'inactiveSectionHeader'
							onClick: => @_toggleDisplayDeactivatedSections()
						},
							# Rotates 90'CW when expanded
							FaIcon('caret-right', {
								className: 'expanded' if @state.displayDeactivatedSections
							})
							R.strong({}, deactivatedSections.size)
							" Deactivated "
							Term (
								if deactivatedSections.size > 1 then 'Sections' else 'Section'
							)
						)

						(if @state.displayDeactivatedSections
							# Deactivated status
							(deactivatedSections.map (section) =>
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
								})
							)
						)
					)
				)
			)

		_toggleDisplayDeactivatedSections: (boolean, cb=(->)) ->
			displayDeactivatedSections = boolean or not @state.displayDeactivatedSections
			@setState {displayDeactivatedSections}, cb

		_toggleDisplayCompletedSections: (boolean, cb=(->)) ->
			displayCompletedSections = boolean or not @state.displayCompletedSections
			@setState {displayCompletedSections}, cb



	SectionView = React.createFactory React.createClass
		displayName: 'SectionView'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: -> {
			displayCancelledTargets: null
			displayCompletedTargets: null
		}

		expandTargetsWithStatus: (status, cb) ->
			switch status
				when 'default'
					cb()
				when 'completed'
					@_toggleDisplayCompletedTargets(true, cb)
				when 'deactivated'
					@_toggleDisplayDeactivatedTargets(true, cb)
				else
					throw new Error "Unknown status: #{status}"

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
			sectionIsInactive = section.get('status') isnt 'default'

			targetIdsByStatus = section.get('targetIds').groupBy (id) ->
				currentTargetRevisionsById.getIn [id, 'status']

			activeTargets = targetIdsByStatus.get('default')
			completedTargets = targetIdsByStatus.get('completed')
			deactivatedTargets = targetIdsByStatus.get('deactivated')


			return R.div({
				id: "section-#{sectionId}"
				className: "section status-#{section.get('status')}"
				key: section.get('id')
			},
				SectionHeader({
					clientFile
					section
					isReadOnly
					renameSection
					getSectionIndex
					addTargetToSection
					onRemoveNewSection
					targetIdsByStatus
					sectionIsInactive
					currentTargetRevisionsById
				})
				(if section.get('targetIds').size is 0
					R.div({className: 'noTargets'},
						"This #{Term 'section'} is empty."
					)
				)

				# TODO: Generalize these 3 into a single component

				(if activeTargets
					R.div({className: 'targets status-default'},
						# Default status
						(activeTargets.map (targetId) =>
							PlanTarget({
								currentRevision: currentTargetRevisionsById.get targetId
								metricsById
								hasTargetChanged: hasTargetChanged targetId
								key: targetId
								isSelected: targetId is selectedTargetId
								sectionIsInactive
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

				(if completedTargets
					R.div({className: 'targets status-completed'},
						R.span({
							className: 'inactiveTargetHeader'
							onClick: => @_toggleDisplayCompletedTargets()
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
							(completedTargets.map (targetId) =>
								PlanTarget({
									currentRevision: currentTargetRevisionsById.get targetId
									metricsById
									hasTargetChanged: hasTargetChanged targetId
									key: targetId
									isSelected: targetId is selectedTargetId
									sectionIsInactive
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
				(if deactivatedTargets
					R.div({className: 'targets status-deactivated'},
						R.span({
							className: 'inactiveTargetHeader'
							onClick: => @_toggleDisplayCancelledTargets()
						},
							# Rotates 90'CW when expanded
							FaIcon('caret-right', {
								className: 'expanded' if @state.displayDeactivatedTargets
							})
							R.strong({}, targetIdsByStatus.get('deactivated').size)
							" Deactivated "
							Term (
								if targetIdsByStatus.get('deactivated').size > 1 then 'Targets' else 'Target'
							)
						)
						(if @state.displayDeactivatedTargets
							# Cancelled statuses
							(deactivatedTargets.map (targetId) =>
								PlanTarget({
									currentRevision: currentTargetRevisionsById.get targetId
									metricsById
									hasTargetChanged: hasTargetChanged targetId
									key: targetId
									isSelected: targetId is selectedTargetId
									sectionIsInactive
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

		_toggleDisplayDeactivatedTargets: (boolean, cb=(->)) ->
			displayDeactivatedTargets = boolean or not @state.displayDeactivatedTargets
			@setState {displayDeactivatedTargets}, cb

		_toggleDisplayCompletedTargets: (boolean, cb=(->)) ->
			displayCompletedTargets = boolean or not @state.displayCompletedTargets
			@setState {displayCompletedTargets}, cb


	SectionHeader = React.createFactory React.createClass
		displayName: 'SectionHeader'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			{
				clientFile
				section
				isReadOnly
				renameSection
				getSectionIndex
				addTargetToSection
				removeNewSection
				targetIdsByStatus
				onRemoveNewSection
				currentTargetRevisionsById
				sectionIsInactive
			} = @props

			sectionStatus = section.get('status')

			# Figure out whether already exists in plan
			isExistingSection = clientFile.getIn(['plan','sections']).some (obj) =>
				obj.get('id') is section.get('id')

			allTargetsAreInactive = not targetIdsByStatus.has('default')

			canSetStatus = isExistingSection and allTargetsAreInactive
			canModify = not isReadOnly and not sectionIsInactive


			return R.div({className: 'sectionHeader'},
				R.div({
					title: "Edit name"
					className: 'sectionName'
				},
					R.span({
						onClick: renameSection.bind(null, section.get('id')) if canModify
					},
						section.get('name')

						(if canModify
							FaIcon('pencil', {className: 'renameIcon'})
						)
					)
				)
				R.div({className: "btn-group btn-group-sm #{showWhen(not sectionIsInactive)}"},
					R.button({
						ref: 'addTarget'
						className: 'addTarget btn btn-primary'
						onClick: addTargetToSection.bind null, section.get('id')
						disabled: not canModify
					},
						FaIcon('plus')
						"Add #{Term 'target'}"
					)
					WithTooltip({
						title: "Create Section Template"
						placement: 'top'
						container: 'body'
					},
						OpenDialogLink({
							className: 'btn btn-default'
							dialog: CreatePlanTemplateDialog
							title: "Create Template from Section"
							sections: Imm.List([section])
							currentTargetRevisionsById
							disabled: isReadOnly
						},
							FaIcon 'wpforms'
						)
					)
				)
				# TODO: Extract to component
				(if canSetStatus
					(if isExistingSection
						(if sectionStatus is 'default'
							R.div({className: 'statusButtonGroup'},
								WithTooltip({
									title: "Deactivate #{Term 'Section'}" unless isReadOnly or @props.hasTargetChanged
									placement: 'top'
									container: 'body'
								},
									OpenDialogLink({
										clientFile
										className: 'statusButton'
										dialog: ModifySectionStatusDialog
										newStatus: 'deactivated'
										sectionIndex: getSectionIndex section.get('id')
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
								WithTooltip({
									title: "Complete #{Term 'Section'}" unless isReadOnly or @props.hasTargetChanged
									placement: 'top'
									container: 'body'
								},
									OpenDialogLink({
										clientFile
										className: 'statusButton'
										dialog: ModifySectionStatusDialog
										newStatus: 'completed'
										sectionIndex: getSectionIndex section.get('id')
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
										title: "Reactivate #{Term 'Section'}"
										message: """
											This will reactivate the #{Term 'section'} so it appears in the #{Term 'client'}
											#{Term 'plan'}, and future #{Term 'progress notes'}.
										"""
										reasonLabel: "Reason for reactivation:"
										disabled: isReadOnly or @props.hasTargetChanged
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
								onClick: onRemoveNewSection
							},
								FaIcon 'times'
							)
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

			targetIsInactive = @props.isReadOnly or @props.isInactive or @props.sectionIsInactive

			return R.div({
				id: "target-#{currentRevision.get('id')}"
				className: [
					"target target-#{currentRevision.get('id')}"
					"status-#{revisionStatus}"
					'isSelected' if @props.isSelected
					'isInactive' if targetIsInactive
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
						onChange: @_updateField.bind null, 'name'
						onFocus: @props.onTargetSelection
						onClick: @props.onTargetSelection
						disabled: targetIsInactive

					})
					(if not @props.hasTargetChanged and @props.isExistingTarget and not @props.sectionIsInactive
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
											disabled: targetIsInactive
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
											disabled: targetIsInactive
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
				)

				R.div({className: 'descriptionContainer'},
					ExpandingTextArea({
						className: 'description field'
						ref: 'descriptionField'
						placeholder: "Describe the current #{Term 'treatment plan'} . . ."
						value: currentRevision.get('description')
						disabled: targetIsInactive
						onChange: @_updateField.bind null, 'description'
						onFocus: @props.onTargetSelection
						onClick: @props.onTargetSelection
					})
				)
				(if not currentRevision.get('metricIds').isEmpty() or @props.isSelected
					R.div({className: 'metrics'},
						R.div({className: 'metricsList'},
							(currentRevision.get('metricIds').map (metricId) =>
								metric = @props.metricsById.get(metricId)

								MetricWidget({
									name: metric.get('name')
									definition: metric.get('definition')
									value: metric.get('value')
									key: metricId
									tooltipViewport: '.view'
									isEditable: false
									allowDeleting: not targetIsInactive
									onDelete: @props.deleteMetricFromTarget.bind(
										null, @props.targetId, metricId
									)
								})
							)
							(if @props.isSelected and not targetIsInactive
								R.button({
									className: "btn btn-link addMetricButton animated fadeIn"
									onClick: @_focusMetricLookupField.bind(null, @props.targetId)
								},
									FaIcon('plus')
									" Add #{Term 'metric'}"
								)
							)
						)
						(unless targetIsInactive
							R.div({
								className: 'metricLookupContainer'
								ref: 'metricLookup'
							},
								MetricLookupField({
									metrics: @props.metricsById.valueSeq().filter (metric) => metric.get('status') is 'default'
									onSelection: @props.addMetricToTarget.bind(
										null, @props.targetId, @_hideMetricInput
									)
									placeholder: "Find / Define a #{Term 'Metric'}"
									isReadOnly: @props.isReadOnly
									onBlur: @_hideMetricInput
								})
							)
						)
					)
				)
			)

		_updateField: (fieldName, event) ->
			newValue = @props.currentRevision.set fieldName, event.target.value
			@props.onTargetUpdate newValue

		_onTargetClick: (event) ->
			@props.onTargetSelection()

			unless (
				(event.target.classList.contains 'field') or
				(event.target.classList.contains 'lookupField') or
				(event.target.classList.contains 'btn')
			)
				@refs.nameField.focus() unless @props.isReadOnly

		_focusMetricLookupField: ->
			$(@refs.metricLookup).show()
			$('.lookupField').focus()

		_hideMetricInput: ->
			$(@refs.metricLookup).hide()


	return {PlanView}


module.exports = {load}
