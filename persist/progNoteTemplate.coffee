# The data structure that defines how a progress note should be structured.

Joi = require 'joi'

{IdSchema} = require './utils'

schema = Joi.object().keys({
	id: IdSchema
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

# TODO
module.exports = {}
