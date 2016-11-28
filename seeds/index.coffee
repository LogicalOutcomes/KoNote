Imm = require 'immutable'
Faker = require 'faker'
Async = require 'async'
Moment = require 'moment'
Fs = require 'fs'

{Users, Persist, generateId} = require '../src/persist'
Create = require './create'

randomNumberUpTo = (max) -> Math.floor(Math.random() * max) + 1

generateClientFile = (metrics, template, eventTypes, cb) ->
	console.group('Generate Client File')

	clientFile = null
	planTargets = null
	sections = null
	targetIds = null
	planTargets = null
	progNotes = null
	progEventsSet = null

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
			Create.planTargets template.planTargets, clientFile, metrics, (err, results) ->
				if err
					cb err
					return

				planTargets = results
				console.log "Created planTargets", planTargets.toJS()
				cb()

		# Apply the target to a section, apply to clientFile, save
		(cb) ->
			sliceSize = Math.floor(planTargets.size / template.clientFileSections)
			targetIds = planTargets.map (target) -> target.get('id')

			x = 0

			Async.times template.clientFileSections, (index, cb) =>
				sectionTargetIds = targetIds.slice(x, x + sliceSize)
				# randomly chooses a status, with a higher probability of 'default'
				randomNumber = randomNumberUpTo 10

				if randomNumber > 7
					status = 'deactivated'
				else if randomNumber < 3
					status = 'completed'
				else
					status = 'default'

				x += sliceSize

				section = Imm.fromJS {
					id: generateId()
					name: Faker.company.bsBuzz()
					targetIds: sectionTargetIds
					status
				}
				cb null, section

			, (err, results) ->
				if err
					cb err
					return

				clientFile = clientFile.setIn(['plan', 'sections'], Imm.List(results).toJS())
				sections = results


				global.ActiveSession.persist.clientFiles.createRevision clientFile, (err, result) ->
					if err
						cb err
						return

					clientFile = result
					console.log "Modified clientFile with plan sections:", clientFile.toJS()
					cb()


		# Write full a progNote, write a note and random metric for each target, in each section
		(cb) ->
			Create.progNotes template.progNotes, {clientFile, sections, planTargets, metrics}, (err, results) ->
				if err
					cb err
					return

				progNotes = results
				console.log "Created #{progNotes.size} progNotes"
				cb()

		# Write a quickNote
		(cb) ->
			Create.quickNotes template.quickNotes, {clientFile}, (err, results) ->
				if err
					cb err
					return

				quickNotes = results
				console.log "Created #{quickNotes.size} quickNotes"
				cb()

		# Write an alert
		(cb) ->
			Create.alert clientFile, (err, result) ->
				if err
					cb err
					return

				alert = result
				console.log "Created alert"
				cb()

		# Create a # of progEvents for each progNote in the clientFile
		(cb) ->
			Async.map progNotes.toArray(), (progNote, cb) ->
				Create.progEvents template.progEvents, {clientFile, progNote, eventTypes}, (err, results) ->
					if err
						cb err
						return

					cb(null, results)

			, (err, results) ->
				if err
					cb err
					return

				progEventsSet = Imm.List(results)
				console.log "Created #{template.progEvents} progEvents for each progNote"
				cb()

		# 1/10 chance that a globalEvent is created from a progEvent
		(cb) ->
			chanceOfGlobalEvent = 1/10

			Async.map progEventsSet.toArray(), (progEvents, cb) ->
				Async.map progEvents.toArray(), (progEvent, cb) ->

					if randomNumberUpTo(1/chanceOfGlobalEvent) is 1
						Create.globalEvent {progEvent}, cb
					else
						cb null

				, (err, results) ->
					if err
						cb err
						return

					cb null, Imm.List(results)

			, (err, results) ->
				if err
					cb err
					return

				globalEvents = Imm.List(results)
				.flatten(true)
				.filter (globalEvent) -> globalEvent?

				console.log "Generated #{globalEvents.size} globalEvents from progEvents
				(#{chanceOfGlobalEvent*100}% chance)"

				cb()

	], (err) ->
		if err
			cb err
			return

		console.groupEnd('Generate Client File')
		cb(null, clientFile)


generateClientFiles = (quantity, metrics, template, eventTypes, cb) ->
	Async.timesSeries quantity, (quantityPosition, cb) ->
		generateClientFile(metrics, template, eventTypes, cb)
	, (err, results) ->
		if err
			cb err
			return

		clientFiles = Imm.List(results)
		cb(null, clientFiles)


runSeries = (templateFileName = 'seedSmall') ->
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
			Fs.readFile "./seeds/templates/#{templateFileName}.json", (err, result) ->
				if err
					if err.code is "ENOENT"
						cb new Error "Template \"#{templateFileName}.json\" does not exist in /templates"
					cb err
					return

				template = JSON.parse(result)
				console.table template

				cb()

		(cb) ->
			Create.accounts template.accounts, (err, results) ->
				if err
					cb err
					return

				accounts = results
				cb()

		# (cb) ->
		# 	Create.planTemplates template.planTemplates, (err, results) ->
		# 		if err
		# 			cb err
		# 			return

		# 		planTemplates = results
		# 		cb()


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
			generateClientFiles template.clientFiles, metrics, template, eventTypes, (err, results) ->
				if err
					cb err
					return

				clientFiles = results
				console.log "#{clientFiles.size} clientFiles generated"
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
				console.log "Created #{programs.size} program link(s) for each clientFile"
				console.groupEnd('Program Links')
				cb()

	], (err) ->
		# Remove our isSeeding property entirely from global
		delete global.isSeeding

		if err
			# Close any currently open logging groups to make sure the error is seen
			# Yeah, this sucks.
			for i in [0...1000]
				console.groupEnd()

			console.error "Seeding failed:"
			console.error err
			console.error err.stack
			return

		console.info "------ Seeding Complete! ------"


module.exports = {runSeries}
