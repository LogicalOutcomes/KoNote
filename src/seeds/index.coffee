Imm = require 'immutable'
Faker = require 'faker'
Async = require 'async'
Moment = require 'moment'
Fs = require 'fs'

{Users, Persist, generateId} = require '../persist'
Create = require './create'

generateClientFile = (metrics, cb) ->
	console.group('Generated Client File')

	clientFile = null
	planTargets = null
	sections = null
	targetIds = null
	planTargets = null
	progEvents = null
	progNotes = null

	Async.series [
		# Create the empty clientFile
		(cb) ->
			Create.clientFile (err, result) ->
				if err
					cb err
					return

				clientFile = result
				console.log "Created clientFile", clientFile.toJS()
				cb()

		# Create planTargets
		(cb) ->
			Create.planTargets 5, {clientFile, metrics}, (err, results) ->
				if err
					cb err
					return

				planTargets = results
				console.log "Created planTargets", planTargets.toJS()
				cb()

		# Apply the target to a section, apply to clientFile, save
		(cb) ->
			targetIds = planTargets
			.map (target) -> target.get('id')

			section = Imm.fromJS {
				id: generateId()
				name: "Aggression Section"
				targetIds
			}

			sections = Imm.List [section]

			clientFile = clientFile.setIn(['plan', 'sections'], sections.toJS())

			global.ActiveSession.persist.clientFiles.createRevision clientFile, (err, result) ->
				if err
					cb err
					return

				clientFile = result
				console.log "Modified clientFile with plan sections:", clientFile.toJS()
				cb()

		# Write a progNote, write a note and random metric for each target, in each section
		(cb) ->
			Create.progNotes 3, {clientFile, sections, planTargets, metrics}, (err, results) ->
				if err
					cb err
					return

				progNotes = results
				console.log "Created progNotes", progNotes.toJS()
				cb()

		# Create a # of progEvents for each progNote in the clientFile
		(cb) ->
			Async.map progNotes.toArray(), (progNote, cb) ->
				Create.progEvents 3, {clientFile, progNote}, (err, results) ->
					if err
						cb err
						return

					cb(null, results)

			, (err, results) ->
				if err
					cb err
					return

				progEvents = Imm.List(results)
				console.log "Created #{progEvents.size} sets of progEvents in total", progEvents.toJS()
				cb()

	], (err) ->
		if err
			cb err
			return

		console.groupEnd('Generated Client File')
		cb(null, clientFile)


generateClientFiles = (quantity, metrics, cb) ->	
	Async.timesSeries quantity, (quantityPosition, cb) ->
		generateClientFile(metrics, cb)
	, (err, results) ->
		if err
			cb err
			return

		clientFiles = Imm.List(results)
		cb(null, clientFiles)


runSeries = (templateFileName) ->
	# First tell the system that we're seeding, to prevent
	# event-driven operations such opening a clientFile
	global.isSeeding = true

	template = null

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
			Fs.readFile "./src/seeds/templates/#{templateFileName}.json", (err, result) -> 
				if err
					if err.code is "ENOENT"
						console.error "#{templateFileName}: Template does not exist."

					cb err
					return

				console.log JSON.parse(result)
				template = JSON.parse(result)

				cb()

		(cb) ->
			Create.accounts template.accounts, (err, results) ->
				if err
					cb err
					return

				accounts = results
				cb()

		(cb) ->
			Create.programs template.programs, (err, results) ->
				if err
					cb err
					return

				programs = results
				cb()		

		(cb) ->
			Create.eventTypes template.eventTypes, (err, results) ->
				if err
					cb err
					return

				eventTypes = results
				cb()		

		(cb) ->
			Create.metrics template.metrics, (err, results) ->
				if err
					cb err
					return

				metrics = results
				cb()

		(cb) ->
			console.group('Client Files')
			generateClientFiles template.clientFiles, metrics, (err, results) ->
				if err
					cb err
					return

				clientFiles = results
				console.log "#{clientFiles.size} clientFiles generated:", clientFiles.toJS()
				console.groupEnd('Client Files')
				cb()

		(cb) ->
			console.group('Program Links')
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
				console.log "Created #{clientFiles.size} link(s) for each of the #{programs.size} program(s)"
				console.groupEnd('Program Links')
				cb()

	], (err) ->
		if err
			console.error "Problem running seeding series:", err
			return

		# Remove our isSeeding property entirely from global
		delete global.isSeeding

		console.log "Finished Seeding Series!"


module.exports = {runSeries}
