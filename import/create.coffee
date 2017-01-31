Imm = require 'immutable'
Async = require 'async'
Moment = require 'moment'

{Users, TimestampFormat, generateId} = require '../src/persist'
{ProgramColors, EventTypeColors} = require '../src/colors'
{stripMetadata} = require '../src/persist/utils'


Create = {}

# Utilities

createData = (dataCollection, obj, cb) ->
	global.ActiveSession.persist[dataCollection].create obj, cb


# Singular create functions

Create.progEvent = ({clientFileId, progNote, title, description, typeId, startTimestamp, endTimestamp, eventTypes}, cb) ->
	progEvent = Imm.fromJS {
		title
		description
		startTimestamp
		endTimestamp
		status: 'default'
		backdate: progNote.get('backdate')
		typeId
		relatedProgNoteId
		authorProgramId: ''
		clientFileId
	}

	createData 'progEvents', progEvent, cb

Create.progNote = ({backDate, clientFile, sections, planTargets, metrics}, cb) ->
	progNoteTemplate = Imm.fromJS Config.templates[Config.useTemplate]

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

	createData 'progNotes', progNote, cb

module.exports = Create
