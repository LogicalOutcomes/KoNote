# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Imm = require 'immutable'
Term = require '../term'

load = (win) ->
	$ = win.jQuery
	Bootbox = win.bootbox
	React = win.React
	R = React.DOM

	{
		FaIcon, renderLineBreaks, showWhen, stripMetadata, formatTimestamp, capitalize
	} = require('../utils').load(win)

	PlanTargetHistory = React.createFactory React.createClass
		displayName: 'PlanTargetHistory'
		mixins: [React.addons.PureRenderMixin]

		propTypes: -> {
			revisions: React.PropTypes.instanceOf Imm.List
		}

		_diffStrings: (oldString, newString) ->
			{diffChars} = require 'diff'

			diffs = diffChars(oldString, newString)
			diffedString = ""

			# Vanilla JS for sake of performance
			for diff in diffs
				diffedString += (
					if diff.added?
						"<span class='added'>#{diff.value}</span>"
					else if diff.removed?
						"<span class='removed'>#{diff.value}</span>"
					else
						diff.value
				)

			return diffedString

		_buildChangeLog: (revision, index) ->
			# Instantiate our changeLog in the currentRevision object
			revision = revision.set 'changeLog', Imm.List()
			revisionId = revision.get 'revisionId'

			# Find previous revision if exists
			previousRevision = if index > 0 then @props.revisions.reverse().get(index - 1) else null

			# No previous revision means this is when it was created!
			if not previousRevision?
				createdPlanTarget = Imm.fromJS {
					property: Term('target')
					action: 'created'
					icon: 'pencil'
				}
				changeLog = revision.get('changeLog').push createdPlanTarget
				return revision.set('changeLog', changeLog)

			# TODO: Generalize these diffs for arrays & strings,
			# so we (hopefully) don't need to update this as the dataModel changes
				
			# Diff the metricIds
			previousMetricIds = previousRevision.get('metricIds')
			currentMetricIds = revision.get('metricIds')

			unless Imm.is previousMetricIds, currentMetricIds
				removedMetricIds = previousMetricIds
				.filterNot (metricId) -> currentMetricIds.contains(metricId)
				.map (metricId) => Imm.fromJS {
					revisionId
					property: Term('metric')
					action: 'removed'
					value: @props.metricsById.getIn([metricId, 'name'])
					icon: 'times'
				}

				addedMetricIds = currentMetricIds
				.filterNot (metricId) -> previousMetricIds.contains(metricId)
				.map (metricId) => Imm.fromJS {
					revisionId
					property: Term('metric')
					action: 'added'
					value: @props.metricsById.getIn([metricId, 'name'])
					icon: 'plus'
				}

				revisedMetricIds = removedMetricIds.concat addedMetricIds
				changeLog = revision.get('changeLog').concat revisedMetricIds
				revision = revision.set('changeLog', changeLog)


			# Diff the name
			previousName = previousRevision.get('name')
			currentName = revision.get('name')			

			unless previousName is currentName				
				diffedName = @_diffStrings(previousName, currentName)

				revisedName = Imm.fromJS {
					revisionId
					property: 'name'
					action: 'revised'
					value: diffedName
					icon: 'arrow-right'
				}

				changeLog = revision.get('changeLog').push revisedName
				revision = revision.set('changeLog', changeLog)


			# Diff the description
			previousDescription = previousRevision.get('description')
			currentDescription = revision.get('description')

			unless previousDescription is currentDescription
				diffedDescription = @_diffStrings(previousDescription, currentDescription)

				revisedDescription = Imm.fromJS {
					revisionId
					property: 'description'
					action: 'revised'
					value: diffedDescription
					icon: 'arrow-right'
				}

				changeLog = revision.get('changeLog').push revisedDescription
				revision = revision.set('changeLog', changeLog)

			# Diff the status
			previousStatus = previousRevision.get('status')
			currentStatus = revision.get('status')

			unless previousStatus is currentStatus
				revisedStatus = Imm.fromJS {
					revisionId
					property: 'status'
					action: 'revised'
					value: currentStatus
					statusReason: revision.get('statusReason')
					icon: if currentStatus is 'completed' then 'check' else 'ban'
				}

				changeLog = revision.get('changeLog').push revisedStatus
				revision = revision.set('changeLog', changeLog)

			return revision		

		render: ->
			# Process revision history to devise change logs
			# They're already in reverse-order, so reverse() to map changes
			revisions = @props.revisions
			.reverse()
			.map(@_buildChangeLog)
			.reverse()

			return R.div({className: 'planTargetHistory'},
				R.div({className: 'heading'}, "#{Term 'Target'} History")

				(if revisions.isEmpty()
					R.div({className: 'noRevisions'},
						"This #{Term 'target'} is new.  ",
						"It won't have any history until the #{Term 'client file'} is saved."
					)
				else
					R.div({className: 'revisions'},
						revisions.map (revision) -> RevisionChangeLog({
							key: revision.get('revisionId')
							revision							
						})
					)
				)				
			)

	RevisionChangeLog = React.createFactory React.createClass
		displayName: 'RevisionChangeLog'
		mixins: [React.addons.PureRenderMixin]

		getInitialState: ->
			return {isSnapshotVisible: null}

		_toggleSnapshot: -> @setState {isSnapshotVisible: not @state.isSnapshotVisible}

		render: ->
			revision = @props.revision
			changeLog = revision.get('changeLog')	

			return R.section({className: 'revision animated fadeIn'},
				R.div({className: 'header'},
					R.div({className: 'author'},
						FaIcon('user')
						revision.get('author')
					)
					R.div({className: 'timestamp'},
						formatTimestamp revision.get('timestamp')
					)
				)
				R.div({className: 'changeLog'},					
					(changeLog.map (entry, index) =>
						ChangeLogEntry({
							key: index
							index
							entry
							revision
							onToggleSnapshot: @_toggleSnapshot
						})
					)
					(if @state.isSnapshotVisible
						RevisionSnapshot(revision)
					)
				)
			)

	ChangeLogEntry = React.createFactory React.createClass
		displayName: 'ChangeLogEntry'
		mixins: [React.addons.PureRenderMixin]

		render: ->
			entry = @props.entry

			R.article({className: 'entry', key: @props.index},
				# Only show snapshotButton on first changeLogEntry
				(if @props.index is 0 and entry.get('action') isnt 'created'
					R.button({
						className: 'btn btn-default btn-xs snapshotButton'
						onClick: @props.onToggleSnapshot
					}, 
						if not @props.isSnapshotVisible then "view" else "hide"
						" snapshot"
					)
				)

				FaIcon(entry.get('icon'))

				R.span({className: 'action'},
					# Different display cases for indication of change
					(if entry.get('action') is 'created'
						"#{capitalize entry.get('action')} new #{entry.get('property')}: "						
					else if entry.get('statusReason')
						"#{capitalize entry.get('value')} #{Term 'target'} because: "
					else
						"#{capitalize entry.get('action')} #{entry.get('property')}: "
					)
				)

				(if entry.get('action') is 'created'
					RevisionSnapshot(@props.revision)
				else
					R.div({
						className: 'value'
						dangerouslySetInnerHTML: {__html: entry.get('value')}
					})
				)
			)

	RevisionSnapshot = (revision) ->
		R.div({className: 'snapshot'},
			R.div({className: 'name'},
				revision.get('name')
			)
			R.div({className: 'description'},
				renderLineBreaks revision.get('description')
			)
		)

	return PlanTargetHistory

module.exports = {load}