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

	rows = []

	progNote = null

	Async.series [

		(cb) ->
			# this creates an array of Row objs, with header names as properties.
			Fs.createReadStream(importFileName).pipe(csv()).on 'data', (data) ->
				rows.push data
				return
			.on 'end', cb

		(cb) ->
			console.log 'rows', rows
			cb()

		(cb) ->
			Async.map rows, (r, cb) ->
				Async.series [
					(cb) ->
						if r.isProgNote is 'TRUE'
							Create.progNote r.backdate, clientFile, (err, result) ->
								if err
									cb err
									return
								#need resulting prognoteid for next step
								progNote = result
								cb()
					(cb) ->
						if r.isEvent is 'TRUE'
							description = "Visited #{r.nameOfHospital}. Discharge Diagnosis:
							#{r.dischargeDiagnosis}. Attending physician: #{r.attendingPhysician}."

							Create.progEvent clientFile, progNote, r.eventTitle, description,
							null, r.startOfVisit, r.endOfVisit, (err, result) ->
								if err
									cb err
									return
								cb()

				], (err) =>
					if err
						console.log err
						return
					cb()

			, (err) ->
				if err
					cb err
					return
				cb()

		(cb) ->
			console.log "end of series"
			cb()


	], (err) =>
		if err
			console.log err
			return

module.exports = {runSeries}
