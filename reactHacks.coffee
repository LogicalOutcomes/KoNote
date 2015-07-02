Assert = require 'assert'
Async = require 'async'

load = (win) =>
	extractState = (root) =>
		# Is this a composite component?
		if root._renderedComponent
			return {
				type: 'composite'
				value: root.getPublicInstance().state
				next: extractState(root._renderedComponent)
			}

		# OK, we reached the raw DOM component, now we can iterate its children

		children = {}

		if root._renderedChildren?
			for childKey in Object.keys(root._renderedChildren)
				children[childKey] = extractState(
					root._renderedChildren[childKey]
				)

		return {
			type: 'dom'
			children
		}

	injectState = (root, state) =>
		switch state.type
			when 'composite'
				Assert root._renderedComponent

				if state.value?
					root.getPublicInstance().replaceState state.value

				injectState root._renderedComponent, state.next
			when 'dom'
				Assert not root._renderedComponent

				Object.keys(state.children).forEach (childKey) =>
					injectState(
						root._renderedChildren[childKey],
						state.children[childKey]
					)
			else
				throw new Error "unknown state node type: #{state.type}"

	saveState = (globalVarName) =>
		global[globalVarName + '-state'] = extractState global[globalVarName]._reactInternalInstance

	loadState = (globalVarName) =>
		injectState global[globalVarName]._reactInternalInstance, global[globalVarName + '-state']

	snapshotDelay = 50

	recorder = null
	record = (globalVarName) =>
		snapshots = []

		recorder = setInterval =>
			snapshots.push extractState global[globalVarName]._reactInternalInstance
		, snapshotDelay

		global[globalVarName + '-snapshots'] = snapshots

	stop = =>
		if recorder
			clearInterval recorder

	playback = (globalVarName) =>
		stop()

		global[globalVarName + '-snapshots'].forEach (snapshot, i) =>
			setTimeout =>
				injectState global[globalVarName]._reactInternalInstance, snapshot
			, i*snapshotDelay

	return {
		extractState
		injectState
		saveState
		loadState
		record
		stop
		playback
	}

module.exports = {load}
