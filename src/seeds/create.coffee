Imm = require 'immutable'
Faker = require 'faker'
Async = require 'async'	
{Users, TimestampFormat, generateId } = require '../persist'
Moment = require 'moment'

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

Create.progNote = ({clientFile, sectionId, targetIds, metrics}, cb) ->
	earliestDate = Moment().subtract(2, 'months')
	daySpan = Moment().diff(earliestDate, 'days')
	randomDay = Math.floor(Math.random() * daySpan) + 1
	randomBackdate = Moment().subtract(randomDay, 'days')
		
	# metricIds = metrics.each(metric).get('id')
	# # have to loop over targets and make a note for each
	# targetIds.each(targetId)
	# # have to loop over each metric and generate a random value for each
	# metricIds = metrics.each(metric).get('id')

	progNote = Imm.fromJS {
		type: 'full'
		status: 'default'
		templateId: generateId
		clientFileId: clientFile.get('id')
		timestamp: randomBackdate.format(TimestampFormat)
		backdate: ''
		units: [
			id: generateId
			type: 'plan'
			name:
			sections: [
			id: sectionId
			name:
				targets: [
					id: targetId
					name:
					notes: Faker.lorem.paragraph()
					metrics: [
						id: metricId
						name:
						definition:
						value: Math.floor Math.random() * 10 + 1
					]
				]
			]
			
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



# createProgEvent = (index, cb) ->
# 	progEvent = Imm.fromJS {
# 		title: Faker.company.bsBuzz()		
# 		description: Faker.lorem.paragraph()		
# 		startTimestamp: 'YYYYMMDDTHHmmssSSSZZ'
# 		endTimestamp: 'YYYYMMDDTHHmmssSSSZZ'
# 		status: 'default'
# 		# statusReason: optional
# 		typeId: 
# 		relatedProgNoteId: 
# 		relatedElement: {
# 			id: 
# 			type: ['progNoteUnit', 'planSection', 'planTarget']
# 		}
# 	}



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
