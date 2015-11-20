# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Async = require 'async'
Joi = require 'joi'
Mkdirp = require 'mkdirp'
Path = require 'path'

ApiBuilder = require './apiBuilder'
{IdSchema, TimestampFormat} = require './utils'

dataModelDefinitions = [
	{
		name: 'clientFile'
		collectionName: 'clientFiles'
		isMutable: true
		indexes: [
			['clientName', 'first']
			['clientName', 'middle']
			['clientName', 'last']
			['recordId']
		]
		schema: Joi.object().keys({
			clientName: Joi.object().keys({
				first: Joi.string()
				middle: Joi.string().allow('')
				last: Joi.string()
			})
			recordId: [Joi.string(), '']
			plan: Joi.object().keys({
				sections: Joi.array().items(
					Joi.object().keys({
						id: IdSchema
						name: Joi.string()
						targetIds: Joi.array().items(
							IdSchema
						)
					})
				)
			})
		})
		children: [
			{
				name: 'progEvent'
				collectionName: 'progEvents'
				isMutable: false
				indexes: [['relatedProgNoteId']]
				schema: Joi.object().keys({
					relatedProgNoteId: IdSchema
					title: Joi.string()
					description: Joi.string().allow('')			
					startTimestamp: Joi.date().format(TimestampFormat).raw()
					endTimestamp: Joi.date().format(TimestampFormat).raw().allow('')
				})
			}
			{
				name: 'planTarget'
				collectionName: 'planTargets'
				isMutable: true
				schema: Joi.object().keys({
					name: Joi.string()
					notes: Joi.string()
					metricIds: Joi.array().items(
						IdSchema
					)
				})
			}
			{
				name: 'progNote'
				collectionName: 'progNotes'
				isMutable: false
				indexes: [['timestamp']]
				schema: [
					Joi.object().keys({
						type: 'basic' # aka "Quick Notes"
						notes: Joi.string()
					})
					Joi.object().keys({
						type: 'full'
						templateId: IdSchema
						sections: Joi.array().items(
							[
								Joi.object().keys({
									id: IdSchema
									type: 'basic'
									name: Joi.string()
									notes: Joi.string().allow('')
									metrics: Joi.array().items(
										Joi.object().keys({
											id: IdSchema
											name: Joi.string()
											definition: Joi.string()
											value: Joi.string().allow('')
										})
									)
								})
								Joi.object().keys({
									id: IdSchema
									type: 'plan'
									name: Joi.string()
									targets: Joi.array().items(
										Joi.object().keys({
											id: IdSchema
											name: Joi.string()
											notes: Joi.string().allow('')
											metrics: Joi.array().items(
												Joi.object().keys({
													id: IdSchema
													name: Joi.string()
													definition: Joi.string()
													value: Joi.string().allow('')
												})
											)
										})
									)
								})
							]
						)
					})
				]
			}
		]
	}
	{
		name: 'progNoteTemplate'
		collectionName: 'progNoteTemplates'
		isMutable: true
		indexes: [['name']]
		schema: Joi.object().keys({
			name: Joi.string()
			sections: Joi.array().items(
				[
					Joi.object().keys({
						type: 'basic'
						name: Joi.string()
						metricIds: Joi.array().items(
							IdSchema
						)
					})
					Joi.object().keys({
						type: 'plan'
						name: Joi.string()
					})
				]
			)
		})
	}

	{
		name: 'metric'
		collectionName: 'metrics'
		isMutable: false
		indexes: [['name']]
		schema: Joi.object().keys({
			name: Joi.string()
			definition: Joi.string()
		})
	}

	{
		name: 'program'
		collectionName: 'programs'
		isMutable: true
		indexes: [['name'], ['colorHex']]
		schema: Joi.object().keys({
			name: Joi.string()
			description: Joi.string()
			colorKeyHSL: Joi.array().items(Joi.number()).length(3)
		})
	}

	# Link a clientFileId to 1 or more programIds
	{
		name: 'clientFileProgramLink'
		collectionName: 'clientFileProgramLinks'
		isMutable: true
		indexes: [['clientFileId'], ['programId'], ['isActive']]
		schema: Joi.object().keys({
			clientFileId: IdSchema
			programId: IdSchema
			isActive: Joi.boolean()
		})
	}
]

getApi = (session) ->
	ApiBuilder.buildApi session, dataModelDefinitions

# TODO This shouldn't be here, since it's derived from the data model, not part of it
setUpDataDirectory = (dataDir, cb) ->
	# Set up top-level directories
	Async.series [
		(cb) ->
			Async.each dataModelDefinitions, (modelDef, cb) ->
				Mkdirp Path.join(dataDir, modelDef.collectionName), cb
			, cb
		(cb) ->
			Mkdirp Path.join(dataDir, '_tmp'), cb
		(cb) ->
			Mkdirp Path.join(dataDir, '_users'), cb
		(cb) ->
			Mkdirp Path.join(dataDir, '_locks'), cb
	], cb

module.exports = {getApi, setUpDataDirectory}
