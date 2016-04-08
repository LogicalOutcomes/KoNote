Imm = require 'immutable'
Faker = require 'faker'
Async = require 'async'	
Moment = require 'moment'

{Users, TimestampFormat, generateId } = require '../persist'
Config = require '../config'

Create = {}

# util 

createData = (dataCollection, obj, cb) ->
	global.ActiveSession.persist[dataCollection].create obj, cb

Create.clientFile = (cb) ->
	first = Faker.name.firstName()
	middle = Faker.name.firstName()
	last = Faker.name.lastName()
	recordId = Faker.random.number().toString()

	clientFile = Imm.fromJS {
		clientName: {first, middle, last}
		recordId: recordId
		plan: {
			sections: []
		}
	}

	createData 'clientFiles', clientFile, cb

#children functions

Create.progEvent = ({clientFile, progNote}, cb) ->
	earliestDate = Moment().subtract(2, 'months')
	daySpan = Moment().diff(earliestDate, 'days')
	randomDay = Math.floor(Math.random() * daySpan) + 1
	randomBackdate = Moment().subtract(randomDay, 'days')
	randomEnddate = Moment().subtract(randomDay, 'days').add(3, 'days')

	relatedProgNoteId = progNote.get('id')
	clientFileId = clientFile.get('id')

	progEvent = Imm.fromJS {
		title: Faker.company.bsBuzz()		
		description: Faker.lorem.paragraph()		
		startTimestamp: randomBackdate.format(TimestampFormat)
		endTimestamp: randomEnddate.format(TimestampFormat)
		status: 'default'
		# statusReason: optional
		typeId: ''
		relatedProgNoteId
		clientFileId
		relatedElement: ''
	}

	createData 'progEvents', progEvent, cb

Create.quickNote = (clientFile, cb) ->
	earliestDate = Moment().subtract(2, 'months')
	daySpan = Moment().diff(earliestDate, 'days')
	randomDay = Math.floor(Math.random() * daySpan) + 1
	randomBackdate = Moment().subtract(randomDay, 'days')

	note = Imm.fromJS {
		type: 'basic'
		status: 'default'
		clientFileId: clientFile.get('id')
		notes: Faker.lorem.paragraph()
		timestamp: randomBackdate.format(TimestampFormat)
		backdate: ''
	}

	createData 'progNotes', note, cb

Create.progNote = ({clientFile, sections, planTargets, metrics}, cb) ->
	earliestDate = Moment().subtract(2, 'months')
	daySpan = Moment().diff(earliestDate, 'days')
	randomDay = Math.floor(Math.random() * daySpan) + 1
	randomBackdate = Moment().subtract(randomDay, 'days')

	progNoteTemplate = Imm.fromJS Config.templates[Config.useTemplate]

	progNoteUnit = progNoteTemplate.getIn(['units', 0])

	# Loop over progNote sections
	progNoteSections = sections.map (section) ->

		# Loop over targetIds, and get the matching planTarget definition
		targets = section.get('targetIds').map (targetId) ->
			planTarget = planTargets.find (target) -> target.get('id') is targetId

			# Loop over metricIds, get the matching metric
			metricNotes = planTarget.get('metricIds').map (metricId) ->
				metric = metrics.find (metric) -> metric.get('id') is metricId

				# Generate fake metric value
				randomNumber = Math.floor(Math.random() * 10) + 1

				# Construct the metric note
				return {
					id: metric.get('id')
					name: metric.get('name')
					definition: metric.get('definition')
					value: randomNumber.toString()
				}


			# Construct the target note
			return {
				id: planTarget.get('id')
				name: planTarget.get('name')
				notes: Faker.lorem.paragraph()
				metrics: metricNotes.toJS()
			}


		# Construct the section as a whole
		return {
			id: section.get('id')
			name: section.get('name')
			targets: targets
		}


	progNote = Imm.fromJS {
		clientFileId: clientFile.get('id')
		type: 'full'
		status: 'default'
		templateId: progNoteTemplate.get('id')
		backdate: ''
		timestamp: randomBackdate.format(TimestampFormat)
		units: [
			{
				id: progNoteUnit.get('id')
				type: progNoteUnit.get('type')
				name: progNoteUnit.get('name')
				sections: progNoteSections.toJS()
			}
		]
	}

	createData 'progNotes', progNote, cb


Create.planTarget = ({clientFile, metrics}, cb) ->
	metricIds = metrics
	.map (metric) -> metric.get('id')
	.toJS()

	target = Imm.fromJS {
		clientFileId: clientFile.get('id')
		name: "Fake Target"
		notes: "Notes Notes"
		metricIds
	}

	createData 'planTargets', target, cb

Create.program = (index, cb) ->
	program = Imm.fromJS({
		name: Faker.company.bsBuzz()
		description: Faker.lorem.paragraph()
		colorKeyHex: Faker.internet.color()
	})

	createData 'programs', program, cb
	
Create.clientFileProgramLink = (clientFile, program, cb) ->
	link = Imm.fromJS({
		clientFileId: clientFile.get('id')
		programId: program.get('id')
		status: 'enrolled'
	})

	createData 'clientFileProgramLinks', link, cb
	
Create.metric = (index, cb) ->
	metric = Imm.fromJS ({
		name: Faker.company.bsBuzz()
		definition: Faker.lorem.paragraph()
	})

	createData 'metrics', metric, cb
	

Create.eventType = (index, cb) ->
	eventType = Imm.fromJS ({
		name: Faker.company.bsBuzz()
		colorKeyHex: Faker.internet.color()
		description: Faker.lorem.paragraph()
		status: 'default'
	})
	createData 'eventTypes', eventType, cb

Create.account = (index, cb) ->
	userName = Faker.lorem.word()
	password = 'password'
	accountType = 'normal'

	Users.Account.create global.ActiveSession.account, userName, password, accountType, (err, newAccount) ->
		if err
			cb err
			return

		cb null, newAccount


# wrappers

Create.clientFiles = (numberOfFiles, cb=(->)) ->
	Async.times numberOfFiles, Create.clientFile, (err, clientFiles) ->
		if err
			console.error err
			cb err
			return

		cb null, Imm.List(clientFiles)
		console.log "created #{numberOfFiles} client files"


  #children

Create.progEvents = (quantity, props, cb) ->
	Async.times quantity, (index, cb) ->
		Create.progEvent(props, cb)
	, (err, results) ->
		if err
			cb err
			return

		console.log "added #{quantity} events to each clientFile"
		cb null, Imm.List(results)

Create.quickNotes = (clientFile, numberOfNotes, cb) ->
	Async.times numberOfNotes, (index, cb) ->
		Create.quickNote(clientFile, cb)
	, (err, results) ->
		if err
			cb err
			return

		console.log "added #{numberOfNotes} notes to each client"
		cb null, Imm.List(results)

Create.progNotes = (quantity, props, cb) ->
	Async.times quantity, (index, cb) ->
		Create.progNote(props, cb)
	, (err, results) ->
		if err
			cb err
			return

		console.log "added #{quantity} progNotes to clientFile"
		cb null, Imm.List(results)
	
Create.planTargets = (quantity, props, cb) ->
	Async.times quantity, (index, cb) ->
		Create.planTarget(props, cb)
	, (err, results) ->
		if err
			cb err
			return

		console.log "added #{quantity} planTargets to clientFile"
		cb null, Imm.List(results)

Create.programs = (numberOfPrograms, cb=(->)) ->
	Async.times numberOfPrograms, Create.program, (err, programs) ->
		if err
			cb err
			return

		cb null, Imm.List(programs)
		console.log "created #{numberOfPrograms} programs"

Create.clientFileProgramLinks = (clientFiles, program, cb) ->
	Async.map clientFiles.toArray(), (clientFile, cb) ->
		Create.clientFileProgramLink clientFile, program, (err, result) ->
			if err 
				cb err
				return

			cb null, Imm.List(result)
	, cb

Create.metrics = (numberOfMetrics, cb=(->)) ->
	Async.times numberOfMetrics, Create.metric, (err, metrics) ->
		if err
			cb err
			return

		cb null, Imm.List(metrics)
		console.log "created #{numberOfMetrics} metrics"

Create.eventTypes = (numberOfEventTypes, cb=(->)) ->
	Async.times numberOfEventTypes, Create.eventType, (err, eventTypes) ->
		if err
			console.error err
			cb err
			return

		cb null, Imm.List(eventTypes)
		console.log "created #{numberOfEventTypes} event types"

Create.accounts = (numberOfAccounts, cb=(->)) ->
	Async.times numberOfAccounts, Create.account, (err, accounts) ->
		if err
			console.error err
			cb err
			return

		cb null, Imm.List(accounts)
		console.log "created #{numberOfAccounts} accounts"


module.exports = Create
