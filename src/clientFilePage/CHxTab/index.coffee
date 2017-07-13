# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Top-level container for CHx Tab and chx-related utlities in the client file
# It holds a transient state of the chx & topic definitions, which accept updates from props (db)

Async = require 'async'
Imm = require 'immutable'

Term = require '../../term'
Persist = require '../../persist'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM
	ReactDOMServer = win.ReactDOMServer
	{findDOMNode} = win.ReactDOM

	CHxView = require('./chxView').load(win)
	RevisionHistory = require('../../revisionHistory').load(win)
	PrintButton = require('../../printButton').load(win)

	{DropdownButton, MenuItem} = require('../../utils/reactBootstrap').load(win, 'DropdownButton', 'MenuItem')
	{FaIcon, showWhen, stripMetadata, scrollToElement} = require('../../utils').load(win)


	CHxTab = React.createFactory React.createClass
		displayName: 'CHxTab'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			currentTopicRevisionsById = @_generateCurrentTopicRevisionsById(@props.chxTopicsById)

			return {
				chx: @props.chx # Transient state for chx
				currentTopicRevisionsById
				selectedTopicId: null
				isCollapsedView: false
				showHistory: true
			}

		componentWillReceiveProps: ({chx, chxTopicsById}) ->
			# Regenerate transient chx data & definitions when is updated upstream (db)
			chxChanged = not Imm.is(chx, @props.chx)
			chxTopicsChanged = not Imm.is(chxTopicsById, @props.chxTopicsById)
			currentTopicRevisionsById = @_generateCurrentTopicRevisionsById(chxTopicsById)

			if chxChanged or chxTopicsChanged
				@setState {
					chx
					currentTopicRevisionsById
				}

		_generateCurrentTopicRevisionsById: (chxTopicsById) ->
			return chxTopicsById.mapEntries ([topicId, topic]) =>
				latestRev = stripMetadata topic.get('revisions').first()
				return [topicId, latestRev]

		render: ->
			{chx, currentTopicRevisionsById} = @state

			# If something selected and that topic has not been deleted
			if @state.selectedTopicId? and currentTopicRevisionsById.has(@state.selectedTopicId)
				# If this topic has been saved at least once
				if @props.chxTopicsById.has @state.selectedTopicId
					selectedTopic = @props.chxTopicsById.get @state.selectedTopicId
				else
					# New topic with no revision history
					selectedTopic = Imm.fromJS {
						id: @state.selectedTopicId
						revisions: []
					}
			else
				selectedTopic = null

			hasChanges = @hasChanges()
			hasCHxSections = not chx.get('sections').isEmpty()


			return R.div({className: 'chxTab'},

				R.div({className: 'leftPane'},

					# TODO: Make component
					R.div({className: "empty #{showWhen not hasCHxSections}"},
						R.div({className: 'message'},
							"This #{Term 'client'} does not currently have any #{Term 'chx topics'}."
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

					# TODO: Make component
					R.div({className: "flexButtonToolbar #{showWhen chx.get('sections').size > 0}"},

						R.button({
							className: 'saveButton'
							disabled: @props.isReadOnly or not hasChanges
							onClick: @_save
						},
							FaIcon('save', {className:'menuItemIcon'})
							R.span({className: 'menuItemText'},
								"Save"
							)
						)

						R.button({
							className: 'discardButton'
							disabled: @props.isReadOnly or not hasChanges
							onClick: @_resetChanges
						},
							FaIcon('undo', {className:'menuItemIcon'})
							R.span({className: 'menuItemText'},
								"Discard"
							)
						)

						R.button({
							className: 'reorderButton'
							onClick: => @_toggleCollapsedView()
						},
							(if @state.isCollapsedView
								R.div({},
									FaIcon('expand', {className:'menuItemIcon'})
									R.span({className: 'menuItemText'},
										" Expand"
									)
								)
							else
								R.div({},
									FaIcon('compress', {className:'menuItemIcon'})
									R.span({className: 'menuItemText'},
										"Collapse"
									)
								)
							)
						)

						PrintButton({
							dataSet: [
								{
									format: 'chx'
									data: {
										sections: chx.get('sections')
										topics: currentTopicRevisionsById
									}
									clientFile: @props.clientFile
								}
							]
							iconOnly: false
							iconClassName: 'menuItemIcon'
							labelClassName: 'menuItemText'
							disabled: hasChanges
						})

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

						R.button({
							className: 'toggleHistoryButton'
							onClick: @_toggleHistoryPane
						},
							(if @state.showHistory
								FaIcon('angle-right', {className:'menuItemIcon'})
							else
								FaIcon('angle-left', {className:'menuItemIcon'})
							)
						)

					)

					CHxView({
						ref: (component) => @chxView = component
						clientFile: @props.clientFile
						chx
						programsById: @props.programsById
						chxTopicsById: @props.chxTopicsById
						currentTopicRevisionsById
						selectedTopicId: @state.selectedTopicId

						isReadOnly: @props.isReadOnly
						isCollapsed: @state.isCollapsedView

						renameSection: @_renameSection
						addTopicToSection: @_addTopicToSection
						removeNewTopic: @_removeNewTopic
						removeNewSection: @_removeNewSection
						hasTopicChanged: @_hasTopicChanged
						updateTopic: @_updateTopic
						setSelectedTopic: @_setSelectedTopic
						addMetricToTopic: @_addMetricToTopic
						deleteMetricFromTopic: @_deleteMetricFromTopic
						getSectionIndex: @_getSectionIndex
						collapseAndSelectTopicId: @_collapseAndSelectTopicId
						toggleCollapsedView: @_toggleCollapsedView

						reorderSection: @_reorderSection
						reorderTopicId: @_reorderTopicId
					})
				)

				R.div({
					className: [
						'rightPane
						topicDetail'
						'collapsed' unless @state.showHistory
					].join ' '
				},
					(if not selectedTopic?
						R.div({className: "noSelection #{showWhen chx.get('sections').size > 0}"},
							"More information will appear here when you select ",
							"a #{Term 'topic'} on the left."
						)
					else
						R.div({className: 'revisionHistoryContainer'},
							RevisionHistory({
								revisions: selectedTopic.get('revisions')
								type: 'chxTopic'
								programsById: @props.programsById
								dataModelName: 'topic'
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
			unless Imm.is @props.chx, @state.chx
				return true

			for topicId in @state.currentTopicRevisionsById.keySeq().toJS()
				if @_hasTopicChanged topicId
					return true

			return false

		_hasTopicChanged: (topicId, currentTopicRevisionsById, chxTopicsById) ->
			# Default to retrieving these values from the component
			currentTopicRevisionsById or= @state.currentTopicRevisionsById
			chxTopicsById or= @props.chxTopicsById

			# Get current revision (normalized) of the specified topic
			currentRev = @_normalizeTopic currentTopicRevisionsById.get(topicId)

			# If this is a new topic
			topic = chxTopicsById.get(topicId, null)
			unless topic
				# If topic is empty
				emptyName = currentRev.get('name') is ''
				emptyDescription = currentRev.get('description') is ''
				if emptyName and emptyDescription
					return false

				return true

			lastRev = topic.getIn ['revisions', 0]

			# Like stripMetaData, but keep timestamp intact
			lastRevNormalized = lastRev
				.delete('revisionId')
				.delete('author')
				.delete('timestamp')
				.delete('authorDisplayName')

			return not Imm.is(currentRev, lastRevNormalized)

		_save: ->
			@_normalizeTopics()
			@_removeUnusedTopics()

			# Wait for state changes to be applied
			@forceUpdate =>
				valid = @_validateTopics()

				unless valid
					Bootbox.alert "Cannot save #{Term 'chx'}: there are empty #{Term 'topic'} fields."
					return

				# Capture these values for use in filtering functions below.
				# This is necessary to ensure that they won't change between
				# now and when the filtering functions are actually called.
				currentTopicRevisionsById = @state.currentTopicRevisionsById
				chxTopicsById = @props.chxTopicsById

				newCHxTopics = currentTopicRevisionsById.valueSeq()
				.filter (topic) =>
					# Only include topics that have not been saved yet
					return not chxTopicsById.has(topic.get('id'))
				.map(@_normalizeTopic)

				updatedCHxTopics = currentTopicRevisionsById.valueSeq()
				.filter (topic) =>
					# Ignore new topics
					unless chxTopicsById.has(topic.get('id'))
						return false

					# Only include topics that have actually changed
					return @_hasTopicChanged(
						topic.get('id'),
						currentTopicRevisionsById,
						chxTopicsById
					)
				.map(@_normalizeTopic)

				@props.updateCHx @state.chx, newCHxTopics, updatedCHxTopics

		_collapseAndSelectTopicId: (selectedTopicId, cb) ->
			@setState {
				isCollapsedView: false
				selectedTopicId
			}, cb

		_toggleCollapsedView: (cb=(->)) ->
			isCollapsedView = not @state.isCollapsedView
			@setState {isCollapsedView}, cb

		_reorderSection: (dragIndex, hoverIndex) ->
			if @props.isReadOnly
				@_showReadOnlyAlert()
				return

			sections = @state.chx.get('sections')
			dragSection = sections.get(dragIndex)

			sections = sections
			.delete(dragIndex)
			.splice(hoverIndex, 0, dragSection)

			chx = @state.chx.set('sections', sections)

			@setState {chx}

		_reorderTopicId: (sectionIndex, dragIndex, hoverIndex) ->
			if @props.isReadOnly
				@_showReadOnlyAlert()
				return

			topicIds = @state.chx.getIn(['sections', sectionIndex, 'topicIds'])
			dragTopic = topicIds.get(dragIndex)

			topicIds = topicIds
			.delete(dragIndex)
			.splice(hoverIndex, 0, dragTopic)

			chx = @state.chx.setIn(['sections', sectionIndex, 'topicIds'], topicIds)

			@setState {chx}

		_showReadOnlyAlert: ->
			Bootbox.alert "Sorry, you can't modify the #{Term 'chx'} while in read-only mode."

		_resetChanges: ->
			Bootbox.confirm "Discard all changes made to the #{Term 'chx'}?", (ok) =>
				if ok
					@setState {
						currentTopicRevisionsById: @_generateCurrentTopicRevisionsById @props.chxTopicsById
						chx: @props.chx
					}

		_normalizeTopics: ->
			@setState (state) =>
				return {
					currentTopicRevisionsById: state.currentTopicRevisionsById.map (topicRev, topicId) =>
						return @_normalizeTopic topicRev
				}

		_normalizeTopic: (topicRev) ->
			trim = (s) -> s.trim()

			# Trim whitespace from fields
			return topicRev
			.update('name', trim)
			.update('description', trim)

		_removeUnusedTopics: ->
			@setState (state) =>
				unusedTopicIds = state.chx.get('sections').flatMap (section) =>
					return section.get('topicIds').filter (topicId) =>
						currentRev = state.currentTopicRevisionsById.get(topicId)
						emptyName = currentRev.get('name') is ''
						emptyDescription = currentRev.get('description') is ''
						noHistory = @props.chxTopicsById.get(topicId, null) is null

						return emptyName and emptyDescription and noMetrics and noHistory

				return {
					chx: state.chx.update 'sections', (sections) =>
						return sections.map (section) =>
							return section.update 'topicIds', (topicIds) =>
								return topicIds.filter (topicId) =>
									return not unusedTopicIds.contains(topicId)

					currentTopicRevisionsById: state.currentTopicRevisionsById.filter (rev, topicId) =>
						return not unusedTopicIds.contains(topicId)
				}

		_validateTopics: -> # returns true iff all valid
			return @state.chx.get('sections').every (section) =>
				return section.get('topicIds').every (topicId) =>
					currentRev = @state.currentTopicRevisionsById.get(topicId)

					emptyName = currentRev.get('name') is ''
					emptyDescription = currentRev.get('description') is ''

					return not emptyName and not emptyDescription


		_toggleHistoryPane: ->
			showHistory = not @state.showHistory
			@setState {showHistory}

		_addSection: ->
			# Build programDropdown markup
			programDropdown = ReactDOMServer.renderToString(
				R.select({
					id: 'programDropdown'
					className: 'form-control'
				},
					R.option({value: ''}, "All #{Term 'Programs'}")
					(@props.clientPrograms.map (program) ->
						R.option({
							key: program.get('id')
							value: program.get('id')
						},
							program.get('name')
						)
					)
				)
			)

			Bootbox.dialog {
				title: "New #{Term 'chx'} #{Term 'section'}"
				message: """
					<div style="display: flex;">
						<div style="flex: 3;">
							<input
								id="sectionNameInput"
								class="form-control"
								placeholder="Enter a #{Term 'section'} name"
							/>
						</div>
						<div style="flex: 2; padding-left: 10px;">
							#{programDropdown}
						</div>
					</div>
				"""
				buttons: {
					cancel: {
						label: "Cancel"
						className: 'btn-default'
					}
					success: {
						label: "Done"
						className: 'btn-success'
						callback: =>
							sectionName = $('#sectionNameInput').val().trim()

							if not sectionName
								Bootbox.alert "A valid #{Term 'section'} name must be provided."
								return

							sectionId = Persist.generateId()
							programId = $('#programDropdown').val() or ''

							newCHx = @state.chx.update 'sections', (sections) =>
								return sections.push Imm.fromJS {
									id: sectionId
									name: sectionName
									topicIds: []
									programId: programId or ''
									status: 'default'
								}

							@setState {chx: newCHx}, =>
								@_addTopicToSection sectionId


					}
				}
			}
			.on('shown.bs.modal', -> $('#sectionNameInput').focus())


		_renameSection: (sectionId) ->
			sectionIndex = @_getSectionIndex sectionId
			section = @state.chx.getIn ['sections', sectionIndex]

			name = section.get('name')
			programId = section.get('programId')

			# Build programDropdown markup
			programDropdown = ReactDOMServer.renderToString(
				R.select({
					id: 'programDropdown'
					className: 'form-control'
					defaultValue: programId or ''
				},
					R.option({value: ''}, "All #{Term 'Programs'}")
					(@props.clientPrograms.map (program) ->
						R.option({
							key: program.get('id')
							value: program.get('id')
						},
							program.get('name')
						)
					)
				)
			)

			Bootbox.dialog {
				title: "Modify #{Term 'chx'} #{Term 'section'}"
				message: """
					<div style="display: flex;">
						<div style="flex: 3;">
							<input
								id="sectionNameInput"
								class="form-control"
								value=#{name}
								placeholder="Enter a #{Term 'section'} name"
							/>
						</div>
						<div style="flex: 2; padding-left: 10px;">
							#{programDropdown}
						</div>
					</div>
				"""
				buttons: {
					cancel: {
						label: "Cancel"
						className: 'btn-default'
					}
					success: {
						label: "Done"
						className: 'btn-success'
						callback: =>
							sectionName = $('#sectionNameInput').val().trim()

							if not sectionName
								Bootbox.alert "A valid #{Term 'section'} name must be provided."
								return

							programId = $('#programDropdown').val() or ''

							updatedSection = section
							.set 'name', sectionName
							.set 'programId', programId

							newCHx = @state.chx.setIn ['sections', sectionIndex], updatedSection
							@setState {chx: newCHx}
					}
				}
			}
			.on('shown.bs.modal', -> $('#sectionNameInput').focus())

		_addTopicToSection: (sectionId) ->
			sectionIndex = @_getSectionIndex sectionId

			topicId = '__transient__' + Persist.generateId()
			newCHx = @state.chx.updateIn ['sections', sectionIndex, 'topicIds'], (topicIds) =>
				return topicIds.push topicId

			newTopic = Imm.fromJS {
				id: topicId
				clientFileId: @props.clientFileId
				status: 'default'
				name: ''
				description: ''
			}
			newCurrentRevs = @state.currentTopicRevisionsById.set topicId, newTopic

			@setState {
				chx: newCHx
				currentTopicRevisionsById: newCurrentRevs
				selectedTopicId: topicId
			}, =>
				# TODO: Refactor w/ CHxView.scrollTo into util
				$container = findDOMNode(@chxView)
				elementId = "topic-#{topicId}"
				$element = win.document.getElementById(elementId)

				topPadding = 50 # TODO: Figure this out programatically

				topOffset = topPadding
				scrollToElement $container, $element, 1000, 'easeInOutQuad', topOffset, (->)

				$("##{elementId} .name.field").focus() # Pre-focus the name field for input

		_removeNewTopic: (sectionId, transientTopicId) ->
			sectionIndex = @_getSectionIndex sectionId

			chx = @state.chx.updateIn ['sections', sectionIndex, 'topicIds'], (topicIds) =>
				topicIndex = topicIds.indexOf transientTopicId
				return topicIds.splice(topicIndex, 1)

			currentTopicRevisionsById = @state.currentTopicRevisionsById.delete transientTopicId

			@setState {chx, currentTopicRevisionsById}

		_removeNewSection: (section) ->
			sectionId = section.get('id')
			sectionIndex = @_getSectionIndex sectionId

			# Update chx
			chx = @state.chx.set 'sections', @state.chx.get('sections').splice(sectionIndex, 1)

			# Filter out all this section's topicIds from currentTopicRevisionsById
			currentTopicRevisionsById = @state.currentTopicRevisionsById.filterNot (topicRevision, topicId) ->
				section.get('topicIds').contains topicId

			@setState {chx, currentTopicRevisionsById}

		_getSectionIndex: (sectionId) ->
			return @state.chx.get('sections').findIndex (section) =>
				return section.get('id') is sectionId

		_updateTopic: (topicId, newValue) ->
			@setState {
				currentTopicRevisionsById: @state.currentTopicRevisionsById.set topicId, newValue
			}

		_setSelectedTopic: (topicId, cb) ->
			# Prevent event obj arg from ftn binds in chxTopic
			cb = (->) unless typeof cb is 'function'

			@setState {selectedTopicId: topicId}, cb


	return CHxTab

module.exports = {load}
