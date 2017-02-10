# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Lists entries of revisions from provided rev-history, with add/removed diffing

Imm = require 'immutable'
DiffMatchPatch = require 'diff-match-patch'
{diffSentences, diffTrimmedLines, diffWordsWithSpace} = require 'diff'

Term = require './term'


load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	MetricWidget = require('./metricWidget').load(win)
	ColorKeyBubble = require('./colorKeyBubble').load(win)
	ProgNoteContents = require('./clientFilePage/progNoteContents').load(win)

	{FaIcon, renderLineBreaks, showWhen,
	stripMetadata, formatTimestamp, capitalize} = require('./utils').load(win)


	RevisionHistory = React.createFactory React.createClass
		displayName: 'RevisionHistory'
		mixins: [React.addons.PureRenderMixin]

		getDefaultProps: -> {
			terms: {}
			metricsById: Imm.List()
			attachments: Imm.List()
			disableSnapshot: false
		}

		propTypes: -> {
			dataModelName: React.PropTypes.string().isRequired()
			revisions: React.PropTypes.instanceOf(Imm.List).isRequired()
			programsById: React.PropTypes.instanceOf(Imm.Map).isRequired()
			attachments: React.PropTypes.instanceOf(Imm.List)
		}

		_diffStrings: (oldString = "", newString = "") ->
			dmp = new DiffMatchPatch()
			# first pass; can lower timeout if too slow
			# dmp.Diff_Timeout = 0.5
			diffs = dmp.diff_main(oldString, newString)
			# measure of similarity
			lev = dmp.diff_levenshtein(diffs)
			# second pass
			if lev > 20
				# compare the diff by sentences and diff by lines
				# use the output that produces the cleanest output (shortest sum of removals)
				diffsSentences = diffSentences(oldString, newString)
				# TODO: newlineIsToken would remove all line-breaks for renderLineBreaks, but might be needed
				# diffsLines = diffTrimmedLines(oldString, newString, {newlineIsToken:true})
				diffsLines = diffTrimmedLines(oldString, newString)
				diffsSentencesTotal = 0
				diffsLinesTotal = 0

				for diff in diffsSentences
					if diff.removed?
						diffsSentencesTotal += diff.value.length

				for diff in diffsLines
					if diff.removed?
						diffsLinesTotal += diff.value.length

				if diffsLinesTotal < diffsSentencesTotal
					diffs = diffsLines
				else
					diffs = diffsSentences

			else
				diffs = diffWordsWithSpace(oldString, newString)

			return R.span({className: 'value'},
				# Iterate over diffs and assign a surrounding span, or just the plain string
				diffs.map (diff, key) ->
					value = renderLineBreaks(diff.value)

					if diff.added?
						R.span({className: 'added', key}, value)
					else if diff.removed?
						R.span({className: 'removed', key}, value)
					else
						value
			)

		_generateChangeLogEntries: (revision, index) ->
			changeLog = Imm.List()

			# Convenience method for adding Imm changeLog entries
			# Replace property name with term from @props when valid
			pushToChangeLog = (entry) =>
				if @props.terms[entry.property]?
					entry.property = @props.terms[entry.property]
				changeLog = changeLog.push Imm.fromJS(entry)

			# Process the changes of an object or Imm.List from its predecessor
			processChanges = (parent, property, value, previousValue) =>
				parentId = if parent.get? then parent.get('id')
				parentName = if parent.get? then parent.get('name')

				# Handle regular values
				if typeof value in ['string', 'number'] and value isnt previousValue
					pushToChangeLog {
						parentId
						parentName
						property
						action: 'revised'
						value: @_diffStrings(previousValue, value)
					}
				# Is it an Imm list? (metrics)
				else if property in ['metric', 'metrics']
					# Generate 'revised' (metric value) changes
					value.forEach (arrayItem) =>
						itemId = arrayItem.get('id')
						itemValue = arrayItem.get('value')
						previousItem = previousValue.find (item) -> item.get('id') is itemId
						previousItemValue = previousItem.get('value')

						if previousItem? and itemValue isnt previousItemValue
							pushToChangeLog {
								parentId
								parentName
								property: "#{Term 'metric'} value"
								action: 'revised'
								item: arrayItem
								value: @_diffStrings(previousItemValue, itemValue)
							}


			# Return only creation change if 0-index, check existence to make sure
			unless index > 0 and @props.revisions.reverse().get(index - 1)?
				pushToChangeLog {
					property: @props.dataModelName
					action: 'created'
				}

				return changeLog


			# Not a first revision, so let's build the diff objects for each property/value
			# compared to the previous revision (ignoring metadata properties)
			previousRevision = stripMetadata @props.revisions.reverse().get(index - 1)
			currentRevision = stripMetadata revision


			currentRevision.entrySeq().forEach ([property, value]) =>
				# Ignore statusReason property, it can't be revised
				return if property is 'statusReason'
				# Account for previousRevision not having this property
				previousRevisionValue = previousRevision.get(property) or ""

				# Plain string & number comparison
				if typeof value in ['string', 'number'] and value isnt previousRevisionValue
					# Unique handling for 'status'
					if property is 'status' and currentRevision.has('statusReason')

						# Special case to convert status 'default' -> 'reactivated'
						if value is 'default' then value = 'reactivated'

						pushToChangeLog {
							property
							action: value
							value
							reason: currentRevision.get('statusReason')
						}
					else
						pushToChangeLog {
							property
							action: 'revised'
							value: @_diffStrings(previousRevisionValue, value)
						}

				# Imm List comparison (we assume existence of isList validates Imm.List)
				else if not Imm.is value, previousRevisionValue

					switch @props.type

						when 'planTarget'
							# Generate 'removed' changes
							previousRevisionValue.forEach (item) ->
								unless value.contains(item)
									pushToChangeLog {
										property
										action: 'removed'
										item
									}
							# Generate 'added' changes
							value.forEach (item) ->
								unless previousRevisionValue.contains(item)
									pushToChangeLog {
										property
										action: 'added'
										item
									}

						when 'progNote'
							value.forEach (unit, unitIndex) =>
								switch unit.get('type')

									when 'basic'
										unit.entrySeq().forEach ([property, value]) =>
											previousValue = previousRevisionValue.getIn [unitIndex, property]
											processChanges(unit, property, value, previousValue)

									when 'plan'
										unit.get('sections').forEach (section, sectionIndex) =>
											section.get('targets').forEach (target, targetIndex) =>
												target.entrySeq().forEach ([property, value]) =>
													# Grab the same target value from prev revision
													previousValue = previousRevisionValue.getIn [
														unitIndex
														'sections', sectionIndex
														'targets', targetIndex, property
													]

													processChanges(target, property, value, previousValue)

									else
										throw new Error "Unknown unit type: #{unit.get('type')}"

						else
							throw new Error "Unknown RevisionHistory 'type': #{@props.type}"

			# Fin.
			return changeLog

		_buildInChangeLog: (revision, index) ->
			changeLog = @_generateChangeLogEntries revision, index
			return revision.set 'changeLog', changeLog

		render: ->
			# Process revision history to devise change logs
			# They're already in reverse-order, so reverse() to map changes
			revisions = @props.revisions
			.reverse()
			.map(@_buildInChangeLog)
			.reverse()

			revisedIds = revisions
			.pop() # Discard creation revision (last one)
			.map (r) -> r.get('changeLog').map (l) -> l.get('parentId')
			.flatten()
			.toSet()

			# Either use the revision's name (ex: target name), or the dataModel name
			firstRevision = revisions.first()

			dataName = if firstRevision? and firstRevision.get('name')
				firstRevision.get('name')
			else
				capitalize(Term @props.dataModelName)


			return R.div({className: 'revisionHistory'},
				R.div({className: 'heading'},
					(unless revisions.isEmpty()
						R.section({className: 'dataName'},
							revisions.first().get('name') or capitalize(Term @props.dataModelName)
						)
					)
					R.section({className: 'title'}, "Revision History")
				)

				(if revisions.isEmpty()
					R.div({className: 'noRevisions'},
						"This #{@props.dataModelName} is new.  ",
						"It won't have any history until the #{Term 'client file'} is saved."
					)
				else
					R.div({className: 'revisions'},
						(revisions.map (revision, index) =>
							RevisionChangeLog({
								key: revision.get('revisionId')
								isFirstRevision: index is (revisions.size - 1)
								revision
								revisedIds
								type: @props.type
								metricsById: @props.metricsById
								programsById: @props.programsById
								dataModelName: @props.dataModelName
								disableSnapshot: @props.disableSnapshot

								progEvents: @props.progEvents
								eventTypes: @props.eventTypes
								planTargetsById: @props.planTargetsById
							})
						)
					)
				)
			)


	RevisionChangeLog = React.createFactory React.createClass
		displayName: 'RevisionChangeLog'
		mixins: [React.addons.PureRenderMixin]
		# TODO: propTypes

		getInitialState: -> {
			isSnapshotVisible: null
		}

		_toggleSnapshot: ->
			@setState {isSnapshotVisible: not @state.isSnapshotVisible}

		render: ->
			{revision, revisedIds} = @props

			changeLog = revision.get('changeLog')

			userProgramId = revision.get('authorProgramId')
			userProgram = @props.programsById.get(userProgramId)

			# Simpler vars to help handle unique cases for revision display
			firstChangeLog = changeLog.first()

			isPlanTarget = @props.type is 'planTarget'
			isProgNote = @props.type in ['progNote', 'quickNote']
			isRevision = firstChangeLog? and firstChangeLog.get('action') is 'revised'
			isTargetStatusChange = isPlanTarget and not isRevision
			isRenameEntry = firstChangeLog? and firstChangeLog.get('property') is 'name'
			isCreationEntry = firstChangeLog? and firstChangeLog.get('action') is 'created'


			if isProgNote and isCreationEntry
				# TODO: Incorporate progEvents to revisionHistory
				# progEvents = @props.progEvents.filter (e) -> e.get('relatedProgNoteId') is revision.get('id')

				if revision.get('type') is 'full'

					filteredProgNote = revision.set 'units', revision.get('units').map (unit) ->
						# Basic unit
						if unit.get('type') is 'basic'
							return if @props.revisedIds.includes(unit.get('id')) then unit else undefined

						# Plan unit
						sections = unit.get('sections')
						.map (section) ->
							section.set 'targets', section.get('targets').filter (target) -> revisedIds.includes target.get('id')
						.filterNot (section) ->
							section.get('targets').isEmpty()

						return unit.set 'sections', sections

					# Filter out any empty units
					filteredProgNote = filteredProgNote.set 'units', filteredProgNote.get('units').filterNot (unit) ->
						unit.get('sections').isEmpty()

					hasMultipleRevisedEntries = filteredProgNote
					.get('units')
					.map (unit) ->
						unit.get('sections').map((s) -> s.get 'targets').flatten(true)
					.flatten(true)
					.count() > 1

				else
					# Quick Note
					isQuickNote = true
					filteredProgNote = revision

				# TODO: Diffing for shiftSummaries (can't edit one yet anyway)
				filteredProgNote = filteredProgNote.remove 'summary'



			return R.section({className: 'revision'},
				R.div({className: 'header'},
					R.div({className: 'author'},
						FaIcon('user')
						revision.get('author')
					)
					R.div({className: 'timestamp'},
						if @props.isFirstRevision and revision.get('backdate')
							"#{formatTimestamp revision.get('backdate')} (late entry)"
						else
							formatTimestamp revision.get('timestamp')

						(if userProgram
							ColorKeyBubble({
								colorKeyHex: userProgram.get('colorKeyHex')
								popup: {
									title: userProgram.get('name')
									content: userProgram.get('description')
									placement: 'left'
								}
							})
						)
					)
				)

				R.div({className: 'changeLog'},
					(if isProgNote and isCreationEntry
						R.article({className: 'entry'},
							R.span({className: 'action'},
								(if isQuickNote
									R.span({className: 'action'},
										"Created original #{Term 'quick note'}:"
									)
								else
									R.span({className: 'action'},
										"Created original #{Term 'target'} "
										if hasMultipleRevisedEntries then "entries" else "entry"
										" as:"
									)
								)
							)

							ProgNoteContents({
								progNote: filteredProgNote
								planTargetsById: @props.planTargetsById
								# TODO: Incorporate progEvents to revisionHistory
								# progEvents
								# eventTypes: @props.eventTypes
							})
						)

					else
						(changeLog.map (entry, index) =>
							ChangeLogEntry({
								key: index
								index
								entry
								revision
								isPlanTarget
								type: @props.type
								dataModelName: @props.dataModelName
								metricsById: @props.metricsById
								onToggleSnapshot: @_toggleSnapshot
								isSnapshotVisible: @state.isSnapshotVisible
								disableSnapshot: @props.disableSnapshot
							})
						)
					)
					(if isPlanTarget and not isTargetStatusChange
						RevisionSnapshot({
							revision
							metricsById: @props.metricsById
							isRenameEntry
						})
					)
				)
			)

	ChangeLogEntry = React.createFactory React.createClass
		displayName: 'ChangeLogEntry'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			entry = @props.entry

			isCreationEntry = entry.get('action') is 'created'
			isRenameEntry = entry.get('property') is 'name'

			# Account for terminology metricIds -> metrics
			if entry.get('property') is 'metricIds'
				entry = entry.set('property', 'metric')

			R.article({className: 'entry'},
				# # TODO: Restore as Diffing selector
				# (if not @props.disableSnapshot and @props.index is 0 and entry.get('action') isnt 'created'
				# 	R.button({
				# 		className: 'btn btn-default btn-xs snapshotButton'
				# 		onClick: @props.onToggleSnapshot
				# 	},
				# 		if not @props.isSnapshotVisible then "view" else "hide"
				# 		" full revision"
				# 	)
				# )

				R.span({className: 'action'},
					# Display full progNote (in revisions) for creation entry
					(if isCreationEntry
						"#{capitalize entry.get('action')} #{entry.get('property')}
						#{if @props.isPlanTarget then ' as:' else ''}"
					else if entry.has('reason') # Status change
						"#{capitalize entry.get('value')} #{@props.dataModelName}"
					else if @props.type is 'progNote'
						R.span({},
							"#{capitalize entry.get('action')} #{entry.get('property')} for "
							R.span({className: 'targetHeader'}, entry.get('parentName'))
						)
					else if entry.has('parentName') and not entry.get('parentName').has? # Parent isn't an Imm Map obj
						"#{capitalize entry.get('action')} #{entry.get('property')} for #{entry.get('parentName')}"
					else
						"#{capitalize entry.get('action')} #{entry.get('property')}"
					)

					": " if not @props.isPlanTarget and not isCreationEntry
				)

				(if isCreationEntry and not @props.disableSnapshot
					# We can show full snapshot for dataModel creation
					RevisionSnapshot({
						revision: @props.revision
						dataModelName: @props.dataModelName
						metricsById: @props.metricsById
						#this is here to show the target name in the first history entry
						isRenameEntry: true
					})

				# Unique handling for metrics
				else if entry.get('property') in [Term('metric'), "#{Term 'metric'} value"]

					if typeof entry.get('item') is 'string'
						# This changeLog entry is a single ID string, so fetch latest metric
						metricId = entry.get('item')
						metric = @props.metricsById.get metricId
					else
						# Assume item is the metric object itself
						metric = entry.get('item')

					MetricWidget({
						value: entry.get('value') # Use diffed value if exists
						isEditable: false
						name: metric.get('name')
						definition: metric.get('definition')
						tooltipViewport: 'article'
						styleClass: 'clear' unless entry.get('value')
					})


				else if entry.get('property') is 'value'
					metric = entry.get('item')

				else if @props.isPlanTarget and entry.get('reason')
					": \"#{entry.get('reason')}\""

				else if not @props.isPlanTarget
					if entry.get('reason') then "\"#{entry.get('reason')}\"" else entry.get('value')
				)

			)


	RevisionSnapshot = ({revision, metricsById, isRenameEntry}) ->
		hasMetrics = revision.get('metricIds')?

		R.div({className: 'snapshot'},

			if isRenameEntry
				R.div({className: 'name'},
					revision.get('name')
				)

			R.div({className: 'description'},
				renderLineBreaks revision.get('description')
			)

			(if hasMetrics
				R.div({className: 'metrics'},
					(revision.get('metricIds').map (metricId) =>
						metric = metricsById.get(metricId)

						MetricWidget({
							isEditable: false
							key: metricId
							name: metric.get('name')
							definition: metric.get('definition')
							tooltipViewport: '.snapshot'
						})
					)
				)
			)
		)


	return RevisionHistory

module.exports = {load}
