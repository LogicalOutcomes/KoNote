# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

Joi = require 'joi'

ApiBuilder = require './apiBuilder'
{IdSchema, TimestampFormat} = require './utils'

dataModelDefinitions = [
	{
		name: 'clientFile'
		collectionName: 'clientFiles'
		isMutable: true
		indexes: [
			['status']
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
			birthDate: Joi.date().format('YYYYMMMDD').raw().allow('')
			status: ['active', 'inactive', 'discharged']
			statusReason: Joi.string().optional()
			recordId: [Joi.string(), '']
			plan: Joi.object().keys({
				sections: Joi.array().items(
					Joi.object().keys({
						id: IdSchema
						name: Joi.string()
						status: ['default', 'deactivated', 'completed']
						statusReason: Joi.string().optional()
						programId: IdSchema.allow('')
						targetIds: Joi.array().items(
							IdSchema
						)
					})
				)
			})
			detailUnits: Joi.array().items(
				Joi.object().keys({
					groupId: IdSchema
					fieldId: IdSchema
					value: Joi.string().allow('')
				})
			)
		})
		children: [
			{
				name: 'progEvent'
				collectionName: 'progEvents'
				isMutable: true
				indexes: [['status'], ['relatedProgNoteId']]
				schema: Joi.object().keys({
					title: Joi.string().allow('')
					description: Joi.string().allow('')
					startTimestamp: Joi.date().format(TimestampFormat).raw()
					endTimestamp: Joi.date().format(TimestampFormat).raw().allow('')
					typeId: IdSchema.allow('')
					relatedProgNoteId: IdSchema
					authorProgramId: IdSchema.allow('')
					backdate: Joi.date().format(TimestampFormat).raw().allow('')
					status: ['default', 'cancelled']
					statusReason: Joi.string().optional()
				})
			}
			{
				name: 'planTarget'
				collectionName: 'planTargets'
				isMutable: true
				indexes: [['status']]
				schema: Joi.object().keys({
					name: Joi.string()
					description: Joi.string().allow('')
					status: ['default', 'deactivated', 'completed']
					statusReason: Joi.string().optional()
					metricIds: Joi.array().items(
						IdSchema
					)
				})
			}
			{
				name: 'progNote'
				collectionName: 'progNotes'
				isMutable: true
				indexes: [['status'], ['timestamp'], ['backdate']]
				schema: [
					Joi.object().keys({
						type: 'basic' # aka "Quick Notes"
						status: ['default', 'cancelled']
						statusReason: Joi.string().optional()
						notes: Joi.string()
						backdate: Joi.date().format(TimestampFormat).raw().allow('')
						authorProgramId: IdSchema.allow('')
						beginTimestamp: Joi.date().format(TimestampFormat).raw().allow('')
						summary: Joi.string().allow('').optional()
					})
					Joi.object().keys({
						type: 'full'
						status: ['default', 'cancelled']
						statusReason: Joi.string().optional()
						templateId: IdSchema
						backdate: Joi.date().format(TimestampFormat).raw().allow('')
						authorProgramId: IdSchema.allow('')
						beginTimestamp: Joi.date().format(TimestampFormat).raw().allow('')
						summary: Joi.string().allow('').optional()
						units: Joi.array().items(
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
									sections: Joi.array().items(
										Joi.object().keys({
											id: IdSchema
											name: Joi.string()
											targets: Joi.array().items(
												Joi.object().keys({
													id: IdSchema
													name: Joi.string()
													description: Joi.string().allow('')
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
									)
								})
							]
						)
					})
				]
			}
			{
				name: 'alert'
				collectionName: 'alerts'
				isMutable: true
				indexes: [['status']]
				schema: Joi.object().keys({
					content: Joi.string().allow('')
					updateReason: Joi.string().optional()
					status: ['default', 'cancelled']
					statusReason: Joi.string().optional()
					authorProgramId: IdSchema.allow('')
				})
			}
			{
				name: 'attachment'
				collectionName: 'attachments'
				isMutable: true
				indexes: [['filename'], ['status'], ['relatedProgNoteId']]
				schema: Joi.object().keys({
					filename: Joi.string()
					encodedData: Joi.string()
					status: ['default', 'cancelled']
					statusReason: Joi.string().optional()
					relatedProgNoteId: IdSchema
				})
			}
		]
	}
	{
		name: 'clientDetailDefinitionGroup'
		collectionName: 'clientDetailDefinitionGroups'
		isMutable: true
		indexes: [['status']]
		schema: Joi.object().keys({
			title: Joi.string()
			status: ['default', 'cancelled']
			fields: Joi.array().items(
				Joi.object().keys({
					id: IdSchema
					name: Joi.string()
					inputType: ['input', 'textarea']
					# height, width, max length? etc
					placeholder: Joi.string().allow('')
				})
			)
		})
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
		name: 'planTemplate'
		collectionName: 'planTemplates'
		isMutable: true
		indexes: [['status'], ['name']]
		schema: Joi.object().keys({
			name: Joi.string()
			description: Joi.string().allow('')
			status: ['default', 'cancelled']
			sections: Joi.array().items(
				[
					Joi.object().keys({
						name: Joi.string()
						programId: IdSchema.allow('')
						targets: Joi.array().items(
							name: Joi.string()
							description: Joi.string().allow('')
							metricIds: Joi.array().items(
								IdSchema
							)
						)
					})
				]
			)
		})
	}

	{
		name: 'metric'
		collectionName: 'metrics'
		isMutable: true
		indexes: [['status'], ['name'], ['customId']]
		schema: Joi.object().keys({
			name: Joi.string()
			definition: Joi.string()
			customId: Joi.string().allow('')
			status: ['default', 'deactivated']
		})
	}

	{
		name: 'program'
		collectionName: 'programs'
		isMutable: true
		indexes: [['status'], ['name'], ['colorKeyHex']]
		schema: Joi.object().keys({
			name: Joi.string()
			description: Joi.string().allow('')
			colorKeyHex: Joi.string().regex(/^#[A-Fa-f0-9]{6}/)
			status: ['default', 'cancelled']
		})
	}

	{
		name: 'eventType'
		collectionName: 'eventTypes'
		isMutable: true
		indexes: [['status']]
		schema: Joi.object().keys({
			name: Joi.string()
			description: Joi.string()
			colorKeyHex: Joi.string().regex(/^#[A-Fa-f0-9]{6}/)
			status: ['default', 'cancelled']
		})
	}

	## Program Links

	{
		name: 'clientFileProgramLink'
		collectionName: 'clientFileProgramLinks'
		isMutable: true
		indexes: [['status'], ['clientFileId'], ['programId']]
		schema: Joi.object().keys({
			clientFileId: IdSchema
			programId: IdSchema
			status: ['enrolled', 'unenrolled']
		})
	}

	{
		name: 'userProgramLink'
		collectionName: 'userProgramLinks'
		isMutable: true
		indexes: [['status'], ['userName'], ['programId']]
		schema: Joi.object().keys({
			userName: IdSchema
			programId: IdSchema
			status: ['assigned', 'unassigned']
		})
	}

	{
		name: 'globalEvent'
		collectionName: 'globalEvents'
		isMutable: true
		indexes: [['status'], ['backdate']]
		schema: Joi.object().keys({
			title: Joi.string().allow('')
			description: Joi.string().allow('')
			startTimestamp: Joi.date().format(TimestampFormat).raw()
			endTimestamp: Joi.date().format(TimestampFormat).raw().allow('')
			typeId: IdSchema.allow('')
			clientFileId: IdSchema
			relatedProgNoteId: IdSchema.allow('')
			relatedProgEventId: IdSchema.allow('')
			programId: IdSchema.allow('')
			backdate: Joi.date().format(TimestampFormat).raw().allow('')
			status: ['default', 'cancelled']
			statusReason: Joi.string().optional()
		})
	}
]

getApi = (backendConfig, session) ->
	return ApiBuilder.buildApi backendConfig, session, dataModelDefinitions

module.exports = {dataModelDefinitions, getApi}
