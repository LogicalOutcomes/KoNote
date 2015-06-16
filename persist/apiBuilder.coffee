Async = require 'async'
Backbone = require 'backbone'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'

CollectionMethods = require './collectionMethods'

{IOError, ObjectNotFoundError} = require './utils'

buildApi = (session, dataModelDefinitions) ->
	eventBus = Object.create Backbone.Events

	result = processModels(session, eventBus, dataModelDefinitions).toJS()

	result.eventBus = eventBus
	result.IOError = IOError
	result.ObjectNotFoundError = ObjectNotFoundError

	return result

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

processModel = (session, eventBus, modelDef, context=Imm.List()) ->
	result = Imm.Map({})

	if modelDef.name is ''
		throw new Error """
			Invalid name: #{JSON.stringify modelDef.name}
		"""

	invalidCollNames = ['', 'eventBus']
	if modelDef.collectionName in invalidCollNames or modelDef.collectionName[0] is '_'
		throw new Error """
			Invalid collection name: #{JSON.stringify modelDef.collectionName}
		"""

	modelDef.indexes or= []
	modelDef.children or= []

	collectionApi = CollectionMethods.createCollectionApi session, eventBus, context, modelDef
	result = result.set modelDef.collectionName, collectionApi

	contextEntry = Imm.Map({
		definition: modelDef
		api: collectionApi
	})
	children = processModels session, eventBus, modelDef.children, context.push(contextEntry)

	if children.has modelDef.name
		throw new Error """
			Child collection name identical to an ancestor's name.  Check data model definitions.
		"""

	result = result.merge children

	return result

module.exports = {buildApi}
