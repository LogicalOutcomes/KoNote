Imm = require 'immutable'
Faker = require 'faker'
Async = require 'async'
Moment = require 'moment'
Fs = require 'fs'
csv = require('csv-parser')

{Users, Persist, generateId} = require '../src/persist'

Create = require './create'

runSeries = (importFileName, clientFile) ->
	console.log 'importFileName', importFileName
	console.log 'clientFile', clientFile.toJS()

	array = []

	Async.series [

		(cb) ->
			# this creates an array of Row objs, with header names as properties.
			Fs.createReadStream(importFileName).pipe(csv()).on 'data', (data) ->
				console.log 'data', data
				array.push data
				return
			.on 'end', cb

		(cb) ->
			console.log 'array', array
			console.log 'array0', array[0]
			console.log 'event', array[0].Event
			cb()

	], (err) =>
		if err
			console.log err
			return





module.exports = {runSeries}
