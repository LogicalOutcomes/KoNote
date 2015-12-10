# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module constructs the persistent object API based on a Session and a set
# of data model definitions.  Essentially, it looks at what collections the
# application intends to use, and generates APIs for each of those collections.

Async = require 'async'
Backbone = require 'backbone'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'

CollectionMethods = require './collectionMethods'

# Generate the persistent object API based on the specified definitions.
# The resulting API will perform operations under the specified user session
# (i.e. all changes will include the user name of the account that is logged
# in).
buildApi = (session, dataModelDefinitions) ->
	eventBus = Object.create Backbone.Events

	result = processModels(session, eventBus, dataModelDefinitions).toJS()

	result.eventBus = eventBus

	return result

# Generate collection APIs for multiple data models and their children
processModels = (session, eventBus, modelDefs, context=Imm.List()) ->
	result = Imm.Map()

	for modelDef in modelDefs
		partialResult = processModel session, eventBus, modelDef, context

		if mapKeysOverlap partialResult, result
			throw new Error "Detected duplicate collection names.  Check data model definitions."

		result = result.merge partialResult

	return result

mapKeysOverlap = (map1, map2) ->
	map1Keys = map1.keySeq().toSet()
	map2Keys = map2.keySeq().toSet()

	# true if there is overlap between the two key sets
	return map1Keys.intersect(map2Keys).size > 0

# Generate collection APIs for a single data model and its children.
processModel = (session, eventBus, modelDef, context=Imm.List()) ->
	# Result will be a set of (collection name, collection API) pairs
	result = Imm.Map({})

	if modelDef.name is ''
		throw new Error """
			Invalid name: #{JSON.stringify modelDef.name}
		"""

	# Validate collection name (eventBus is reserved)
	invalidCollNames = ['', 'eventBus']
	if modelDef.collectionName in invalidCollNames or modelDef.collectionName[0] is '_'
		throw new Error """
			Invalid collection name: #{JSON.stringify modelDef.collectionName}
		"""

	modelDef.indexes or= []
	modelDef.children or= []

	# Create the collection API for this data model
	collectionApi = CollectionMethods.createCollectionApi session, eventBus, context, modelDef

	# Add the API to the result set
	result = result.set modelDef.collectionName, collectionApi

	# Process the children of this data model
	# That processing will include this data model as a context entry,
	# since the children have this data model as a parent
	contextEntry = Imm.Map({
		definition: modelDef
		api: collectionApi
	})
	children = processModels session, eventBus, modelDef.children, context.push(contextEntry)

	if children.has modelDef.name
		throw new Error """
			Child collection name identical to an ancestor's name.  Check data model definitions.
		"""

	# Merge in the results from processing the children
	result = result.merge children

	return result

module.exports = {buildApi}
