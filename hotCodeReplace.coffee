# Tools for implementing hot code replace.
#
# This module provides methods for snapshotting a React render tree.
#
# Note: this module depends on the following internal React v0.13.3 properties:
#
#  - ReactComponent._reactInternalInstance
#    either a ReactCompositeComponentWrapper or a ReactDOMComponent
#
#  - ReactCompositeComponentWrapper.getPublicInstance()
#    returns a ReactComponent
#
#  - ReactCompositeComponentWrapper._renderedComponent
#    either a ReactCompositeComponentWrapper or a ReactDOMComponent
#
#  - ReactDOMComponent._renderedChildren
#    either null or an object mapping child keys to children.
#    each child is either a ReactCompositeComponentWrapper or a ReactDOMComponent

Assert = require 'assert'
Async = require 'async'
Imm = require 'immutable'

load = (win) =>
	takeSnapshot = (rootComponent) =>
		return extractState rootComponent._reactInternalInstance

	restoreSnapshot = (rootComponent, snapshot) =>
		errors = injectState rootComponent._reactInternalInstance, snapshot

		if errors.size > 0
			console.error "#{errors.size} error(s) occurred while restoring state snapshot:"

			errors.forEach (err) =>
				console.error "HCR restoration error: #{err.toString()}"

			masterError = new Error("snapshot restoration partially failed")
			masterError.causes = errors
			throw masterError

	extractState = (root) =>
		# Is this a composite component?
		if root._renderedComponent
			return Imm.Map {
				type: 'composite'
				value: root.getPublicInstance().state
				next: extractState root._renderedComponent
			}

		# OK, we reached the raw DOM component, now we can iterate its children
		return Imm.Map {
			type: 'dom'
			children: Imm.Map(root._renderedChildren or {})
			.map (renderedChild) =>
				return extractState renderedChild
		}

	injectState = (root, state) =>
		switch state.get('type')
			when 'composite'
				unless root._renderedComponent?
					return Imm.List([
						new Error "expected composite but found DOM node"
					])

				if state.get('value')?
					root.getPublicInstance().replaceState state.get('value')

				return injectState root._renderedComponent, state.get('next')
			when 'dom'
				if root._renderedComponent
					return Imm.List([
						new Error "expected DOM node but found composite"
					])

				childErrors = state.get('children').entrySeq().flatMap ([childKey, childState]) =>
					renderedChild = root._renderedChildren[childKey]

					unless renderedChild
						return Imm.List([
							new Error "missing child with key #{JSON.stringify childKey}"
						])

					return injectState renderedChild, childState
				.toList()

				expectedChildCount = state.get('children').size
				actualChildCount = Object.keys(root._renderedChildren or {}).length
				if expectedChildCount isnt actualChildCount
					return childErrors.push new Error(
						"expected #{expectedChildCount} children but found #{actualChildCount}"
					)

				return childErrors
			else
				throw new Error "unknown state node type: #{state.get('type')}"

	return {
		takeSnapshot
		restoreSnapshot
	}

module.exports = {load}
