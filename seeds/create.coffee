Imm = require 'immutable'
Faker = require 'faker'
Async = require 'async'
Moment = require 'moment'

Config = require '../src/config'
{Users, TimestampFormat, generateId} = require '../src/persist'
{ProgramColors, EventTypeColors} = require '../src/colors'
{stripMetadata} = require '../src/persist/utils'


Create = {}

# Utilities

createData = (dataCollection, obj, cb) ->
	global.ActiveSession.persist[dataCollection].create obj, cb


# Singular create functions

Create.clientFile = (cb) ->
	first = Faker.name.firstName()
	middle = Faker.name.firstName()
	last = Faker.name.lastName()
	recordId = Faker.random.number().toString()

	earliestDate = Moment().subtract(29000, 'days')
	daySpan = Moment().diff(earliestDate, 'days')
	randomDay = Math.floor(Math.random() * daySpan) + 1
	birthDate = Moment().subtract(randomDay, 'days').format('YYYYMMMDD')

	clientFile = Imm.fromJS {
		clientName: {first, middle, last}
		recordId: recordId
		birthDate
		status: 'active'
		plan: {
			sections: []
		}
		detailUnits: []
	}

	createData 'clientFiles', clientFile, cb

Create.globalEvent = ({progEvent}, cb) ->
	globalEvent = Imm.fromJS {
		title: progEvent.get('title')
		description: progEvent.get('description')
		startTimestamp: progEvent.get('startTimestamp')
		endTimestamp: progEvent.get('endTimestamp')
		typeId: progEvent.get('typeId')
		clientFileId: progEvent.get('clientFileId')
		relatedProgNoteId: progEvent.get('relatedProgNoteId')
		relatedProgEventId: progEvent.get('id')
		programId: progEvent.get('authorProgramId')
		backdate: progEvent.get('backdate')
		status: progEvent.get('status')
		statusReason: progEvent.get('statusReason')
	}

	createData 'globalEvents', globalEvent, cb

Create.progEvent = ({clientFile, progNote, eventTypes}, cb) ->
	earliestDate = Moment().subtract(2, 'months')
	daySpan = Moment().diff(earliestDate, 'days')
	randomDay = Math.floor(Math.random() * daySpan) + 1
	randomBackdate = Moment().subtract(randomDay, 'days')
	randomDaySpan = Math.floor(Math.random() * 10) + 1
	randomEnddate = Moment().subtract(randomDay, 'days').add(randomDaySpan, 'days')

	eventTypeIds = eventTypes
	.map (eventType) -> eventType.get('id')
	.toJS()

	randomIndex = Math.floor(Math.random() * eventTypeIds.length)
	randomTypeId = eventTypeIds[randomIndex]
	relatedProgNoteId = progNote.get('id')
	clientFileId = clientFile.get('id')

	progEvent = Imm.fromJS {
		title: Faker.company.bsBuzz()
		description: Faker.lorem.paragraph()
		startTimestamp: randomBackdate.format(TimestampFormat)
		endTimestamp: randomEnddate.format(TimestampFormat)
		status: 'default'
		# statusReason: optional
		backdate: progNote.get('backdate')
		typeId: randomTypeId
		relatedProgNoteId
		authorProgramId: ''
		clientFileId
	}

	createData 'progEvents', progEvent, cb

Create.quickNote = ({clientFile}, cb) ->
	earliestDate = Moment().subtract(2, 'months')
	daySpan = Moment().diff(earliestDate, 'days')
	randomDay = Math.floor(Math.random() * daySpan) + 1
	randomBackdate = Moment().subtract(randomDay, 'days')

	quickNote = Imm.fromJS {
		type: 'basic'
		status: 'default'
		clientFileId: clientFile.get('id')
		notes: Faker.lorem.paragraph()
		timestamp: randomBackdate.format(TimestampFormat)
		backdate: ''
		authorProgramId: ''
		beginTimestamp: ''
	}

	createData 'progNotes', quickNote, cb

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
				description: planTarget.get('description')
				notes: Faker.lorem.paragraph()
				metrics: metricNotes.toJS()
			}

		# Construct the section as a whole
		return {
			id: section.get('id')
			name: section.get('name')
			targets: targets
		}


	# 1/3 chance of having a summary
	hasSummary = (Math.floor(Math.random() * 3) + 1) is 3


	progNote = Imm.fromJS {
		clientFileId: clientFile.get('id')
		type: 'full'
		status: 'default'
		templateId: progNoteTemplate.get('id')
		backdate: ''
		timestamp: randomBackdate.format(TimestampFormat)
		authorProgramId: ''
		beginTimestamp: ''
		summary: if hasSummary then Faker.lorem.paragraph() else ''
		units: [
			{
				id: progNoteUnit.get('id')
				type: progNoteUnit.get('type')
				name: progNoteUnit.get('name')
				sections: progNoteSections
			}
		]
	}

	createData 'progNotes', progNote, cb

Create.alert = (clientFile, cb) ->
	clientFileId = clientFile.get('id')
	alert = Imm.fromJS {
		content: Faker.lorem.paragraph()
		clientFileId
		status: 'default'
		statusReason: 'Seeded'
		updateReason: 'Seeded'
		authorProgramId: ''
	}

	createData 'alerts', alert, cb

Create.planTarget = (clientFile, metrics, cb) ->
	metricIds = metrics
	.map (metric) -> metric.get('id')
	.toJS()

	# randomly chooses a status, with a higher probability of 'default'
	randomNumber = Math.floor(Math.random() * 10) + 1

	if randomNumber > 8
		status = 'deactivated'
	else if randomNumber < 2
		status = 'completed'
	else
		status = 'default'

	target = Imm.fromJS {
		clientFileId: clientFile.get('id')
		name: Faker.company.bsBuzz()
		description: Faker.lorem.paragraph()
		status
		metricIds
	}

	createData 'planTargets', target, cb

Create.planTargetRevision = (target, cb) ->
	newDescription = Faker.lorem.paragraph()
	updatedPlanTarget = target.set 'description', newDescription

	global.ActiveSession.persist.planTargets.createRevision updatedPlanTarget, cb

Create.program = (index, cb) ->
	program = Imm.fromJS({
		name: Faker.company.bsBuzz()
		description: Faker.lorem.paragraph()
		status: 'default'
		# chooses a hexColor randomly from an imported list of hexcolors
		colorKeyHex: ProgramColors.get(Math.floor(Math.random() * ProgramColors.size))
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
		status: 'default'
	})

	createData 'metrics', metric, cb


Create.eventType = (index, cb) ->
	eventType = Imm.fromJS ({
		name: Faker.company.bsBuzz()
		# chooses a hexColor randomly from an imported list of hexcolors
		colorKeyHex: EventTypeColors.get(Math.floor(Math.random() * EventTypeColors.size))
		description: Faker.lorem.paragraph()
		status: 'default'
	})

	createData 'eventTypes', eventType, cb

Create.account = (index, cb) ->
	userName = 'user' + Faker.random.number()
	displayName = 'userDisplay' + Faker.random.number()
	password = 'password'
	accountType = 'normal'

	Users.Account.create global.ActiveSession.account, userName, displayName, password, accountType, cb

Create.planTemplate = (index, cb) ->
	planTemplate = Imm.fromJS {
		name: Faker.company.bsBuzz()
		sections: [
			{
				name: Faker.company.bsBuzz()
				targets: [
					{
						name: Faker.company.bsBuzz()
						description: Faker.lorem.paragraph()
						metricIds: []
					}
				]
			},
			{
				name: Faker.company.bsBuzz()
				targets: [
					{
						name: Faker.company.bsBuzz()
						description: Faker.lorem.paragraph()
						metricIds: []
					}
				]
			}
		]
	}



# Multi create functions

Create.clientFiles = (quantity, cb=(->)) ->
	Async.times quantity, Create.clientFile, (err, clientFiles) ->
		if err
			cb err
			return

		console.log "Created #{quantity} clientFiles"
		cb null, Imm.List(clientFiles)

Create.progEvents = (quantity, props, cb) ->
	Async.times quantity, (index, cb) ->
		Create.progEvent(props, cb)
	, (err, results) ->
		if err
			cb err
			return

		cb null, Imm.List(results)

Create.quickNotes = (quantity, props, cb) ->
	Async.times quantity, (index, cb) ->
		Create.quickNote(props, cb)
	, (err, results) ->
		if err
			cb err
			return

		cb null, Imm.List(results)

Create.progNotes = (quantity, props, cb) ->
	Async.times quantity, (index, cb) ->
		Create.progNote(props, cb)
	, (err, results) ->
		if err
			cb err
			return

		cb null, Imm.List(results)

Create.planTargets = (quantity, clientFile, metrics, cb) ->
	sliceSize = Math.floor(metrics.size / quantity)
	x = 0

	Async.times quantity, (index, cb) =>
		targetMetrics = metrics.slice(x, x + sliceSize)
		Create.planTarget(clientFile, targetMetrics, cb)
		x += sliceSize
	, (err, results) ->
		if err
			cb err
			return

		console.log "Created #{quantity} planTargets"
		cb null, Imm.List(results)

Create.planTargetRevisions = (quantity, planTarget, cb) ->
	Async.times quantity, (index, cb) =>
		Create.planTargetRevision(planTarget, cb)
	, (err, results) ->
		if err
			cb err
			return
		cb null, Imm.List(results)

Create.programs = (quantity, cb) ->
	Async.times quantity, Create.program, (err, programs) ->
		if err
			cb err
			return

		console.log "Created #{quantity} programs"
		cb null, Imm.List(programs)

Create.clientFileProgramLinks = (clientFiles, program, cb) ->
	Async.map clientFiles.toArray(), (clientFile, cb) ->
		Create.clientFileProgramLink clientFile, program, (err, result) ->
			if err
				cb err
				return

			cb null, Imm.List(result)
	, cb

Create.metrics = (quantity, cb) ->
	Async.times quantity, Create.metric, (err, metrics) ->
		if err
			cb err
			return

		console.log "Created #{quantity} metrics"
		cb null, Imm.List(metrics)

Create.eventTypes = (quantity, cb) ->
	Async.times quantity, Create.eventType, (err, eventTypes) ->
		if err
			cb err
			return

		console.log "Created #{quantity} eventTypes"
		cb null, Imm.List(eventTypes)

Create.accounts = (quantity, cb) ->
	Async.times quantity, Create.account, (err, accounts) ->
		if err
			cb err
			return

		console.log "Created #{quantity} accounts"
		cb null, Imm.List(accounts)

Create.planTemplates = (quantity, cb) ->
	Async.times quantity, Create.planTemplate, (err, planTemplates) ->
		if err
			cb err
			return

		console.log "Created #{quantity} planTemplates"
		cb null, Imm.List(planTemplates)


module.exports = Create
