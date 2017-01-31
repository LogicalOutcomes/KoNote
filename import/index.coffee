Imm = require 'immutable'
Faker = require 'faker'
Async = require 'async'
Moment = require 'moment'
Fs = require 'fs'
csv = require('csv-parser')

{Users, Persist, generateId} = require '../src/persist'

Create = require './create'

runSeries = (importFileName) ->
	console.log "in migrate index.coffee"
	console.log 'importFileName', importFileName

	Fs.createReadStream(importFileName).pipe(csv()).on 'data', (data) ->
	  console.log 'data', data
	  return






module.exports = {runSeries}
