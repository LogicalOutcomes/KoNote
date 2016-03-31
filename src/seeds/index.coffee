Imm = require 'immutable'
Faker = require 'faker'
Async = require 'async'	
Moment = require 'moment'

{Users, Persist} = require '../persist'
Create = require './create'


runSeries = ->
	clientFiles = null
	programs = null
	links = null
	metrics = null
	eventTypes = null
	accounts = null
	quickNotes = null
	planTargets = null

	Async.series [
		(cb) -> 
			Create.clientFiles 3, (err, result) ->
				if err
					cb err
					return

				clientFiles = result
				cb()
		(cb) ->
			Create.programs 2, (err, result) ->
				if err
					cb err
					return

				programs = result
				cb()
		(cb) ->
			Async.map programs.toArray(), (program, cb) ->
				Create.clientFileProgramLinks clientFiles, program, (err, result) ->
					if err 
						cb err
						return

					cb null, Imm.List(result)
			, (err, result) ->
				if err
					cb err
					return

				links = Imm.List(result)
				cb()
		(cb) ->
			Create.metrics 1, (err, result) ->
				if err
					cb err
					return

				metrics = result
				cb()
		(cb) ->
			Create.eventTypes 1, (err, result) ->
				if err
					cb err
					return

				eventTypes = result
				cb()
		(cb) ->
			Create.accounts 0, (err, result) ->
				if err
					cb err
					return

				accounts = result
				cb()		

		#children

		(cb) ->
			Async.map clientFiles.toArray(), (clientFile, cb) ->
				Create.quickNotes clientFile, 3, (err, result) ->
					if err
						cb err
						return
					cb null, Imm.List(result)

			, (err, result) ->
				if err
					cb err
					return
				quickNotes = Imm.List(result)
				cb()


		# (cb) ->
		# 	#should add a single planTarget to each client file
		# 	createPlanTargets clientFiles, metrics (err, result) ->
		# 		if err
		# 			cb err
		# 			return

		# 		planTargets = result
		# 		cb()



	], (err) ->
		if err
			console.error err
			return




module.exports = {
	
	runSeries

}

