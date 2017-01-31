Imm = require 'immutable'
Faker = require 'faker'
Async = require 'async'
Moment = require 'moment'
Fs = require 'fs'

{Users, Persist, generateId} = require '../src/persist'

Create = require './create'

runSeries = (importFileName) ->
	console.log "in migrate index.coffee"
	console.log 'importFileName', importFileName






module.exports = {runSeries}
