Imm = require 'immutable'
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

Create.progEvent = (clientFile, progNote, title, description, eventType, startOfVisit, endOfVisit, eventTypes, cb) ->

	startTimestamp = Moment(startOfVisit, "YYYY-MMM-DD").format(TimestampFormat)
	endTimestamp = Moment(endOfVisit, "YYYY-MMM-DD").format(TimestampFormat)

	typeId = eventTypes.find (type) ->
		type.get('name') is eventType
	.get('id')

	progEvent = Imm.fromJS {
		title
		description
		startTimestamp
		endTimestamp
		status: 'default'
		backdate: progNote.get('backdate')
		typeId
		relatedProgNoteId: progNote.get('id')
		authorProgramId: ''
		clientFileId: clientFile.get('id')
	}

	createData 'progEvents', progEvent, cb

Create.progNote = (backdate, clientFile, cb) ->

	progNoteTemplate = Imm.fromJS Config.templates[Config.useTemplate]
	backdate = Moment(backdate, "YYYY-MMM-DD").format(TimestampFormat)

	progNote = Imm.fromJS {
		clientFileId: clientFile.get('id')
		type: 'full'
		status: 'default'
		templateId: progNoteTemplate.get('id')
		backdate
		authorProgramId: ''
		beginTimestamp: ''
		summary: ''
		units: []
	}

	console.log 'creating progNote....', progNote.toJS()

	createData 'progNotes', progNote, cb


module.exports = Create
