Fs = require 'fs'
Imm = require 'immutable'
Mkdirp = require 'mkdirp'
Moment = require 'moment'
Path = require 'path'

{generateId, SafeTimestampFormat, validate} = require './utils'

read = (objectPath, schema, cb) ->
	Fs.readFile objectPath, (err, buf) ->
		if err
			cb err
			return

		parsed = JSON.parse buf
		validate parsed, schema, (err, parsed) ->
			if err
				cb err
				return

			cb null, Imm.fromJS parsed

write = (object, objectPath, schema, cb) ->
	unless object.get('id')?
		throw new Error "Cannot write ID-less object to #{JSON.stringify objectPath}"

	unless object.get('timestamp')?
		object = object.set 'timestamp', Moment().format()

	jsObject = object.toJS()

	validate jsObject, schema, (err, jsObject) ->
		if err
			cb err
			return

		Mkdirp Path.dirname(objectPath), (err) ->
			if err
				cb err
				return

			Fs.writeFile objectPath, JSON.stringify(jsObject), (err) ->
				if err
					cb err
					return

				cb null, Imm.fromJS jsObject

module.exports = {read, write}
