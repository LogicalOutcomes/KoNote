Joi = require 'joi'

ApiBuilder = require './apiBuilder'
{IdSchema} = require './utils'

dataModelDefinitions = [
	{
		name: 'clientFile'
		collectionName: 'clientFiles'
		isMutable: true
		indexes: [
			['clientName', 'first'], 
			['clientName', 'middle'], 
			['clientName', 'last'],
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
]

getApi = (session) ->
	ApiBuilder.buildApi session, dataModelDefinitions

module.exports = {getApi}
