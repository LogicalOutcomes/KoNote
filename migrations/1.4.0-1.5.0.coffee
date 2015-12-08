Assert = require 'assert'
Async = require 'async'
Base64url = require 'base64url'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'
Moment = require 'moment'

{SymmetricEncryptionKey, PrivateKey, PublicKey} = require '../persist/crypto'
{TimestampFormat} = require '../persist/utils'



# /////////////////// Generic Utilities ///////////////////


loadGlobalEncryptionKey = (dataDir, userName, password, cb) =>
	userDir = Path.join(dataDir, '_users', userName)

	accountKeyId = null
	accountKeyInfo = null
	accountKey = null
	privateInfo = null
	accountType = null
	decryptedAccount = null

	Async.series [
		(cb) ->
			Fs.readdir userDir, (err, fileNames) ->
				if err
					if err.code is 'ENOENT'
						cb new UnknownUserNameError()
						return

					cb err
					return

				# Find the highest (i.e. most recent) account key ID
				accountKeyId = Imm.List(fileNames)
				.filter (fileName) ->
					return fileName.startsWith 'account-key-'
				.map (fileName) ->
					return Number(fileName['account-key-'.length...])
				.max()

				cb()
		(cb) ->
			Fs.readFile Path.join(userDir, "account-key-#{accountKeyId}"), (err, buf) ->
				if err
					cb err
					return

				accountKeyInfo = JSON.parse buf
				cb()
		(cb) ->
			SymmetricEncryptionKey.derive password, accountKeyInfo.kdfParams, (err, result) ->
				if err
					cb err
					return

				pwEncryptionKey = result

				# Use password to decrypt account key
				encryptedAccountKey = Base64url.toBuffer(accountKeyInfo.accountKey)
				try
					accountKeyBuf = pwEncryptionKey.decrypt(encryptedAccountKey)
				catch err
					console.error err.stack

					# If decryption fails, we're probably using the wrong key
					cb new IncorrectPasswordError()
					return

				accountKey = SymmetricEncryptionKey.import(accountKeyBuf.toString())

				cb()
		(cb) =>
			Fs.readFile Path.join(userDir, 'private-info'), (err, buf) ->
				if err
					cb err
					return

				privateInfo = JSON.parse accountKey.decrypt buf
				cb()
	], (err) =>
		if err
			cb err
			return

		globalEncryptionKey = SymmetricEncryptionKey.import privateInfo.globalEncryptionKey
		cb null, globalEncryptionKey

forEachFile = (parentDir, loopBody, cb) ->
	console.log("For each file in #{JSON.stringify parentDir}:")

	fileNames = null

	Async.series [
		(cb) ->
			Fs.readdir parentDir, (err, result) ->
				if err
					cb err
					return

				fileNames = result
				console.info ">> fileNames:", fileNames
				cb()
		(cb) ->
			Async.eachSeries fileNames, (fileName, cb) ->
				console.log("Processing #{JSON.stringify Path.join(parentDir, fileName)}.")

				loopBody fileName, cb
			, cb
	], (err) ->
		if err
			cb err
			return

		console.log("Done iterating files in #{JSON.stringify parentDir}.")

		cb()

createEmptyDirectory = (parentPath, dirName, cb) ->
	newDirPath = Path.join parentPath, dirName
	console.info "newDirPath", newDirPath

	Fs.mkdir newDirPath, (err) ->
		if err
			if err.code is 'EEXIST'
				console.error "Directory #{newDirPath} already exists", err
				cb()
				return

			cb err
			return

		console.log "Created new directory '#{dirName}' at: #{newDirPath}"
		cb()

readFileData = (filePath, globalEncryptionKey, cb) ->
	console.log "Reading file: '#{filePath}'"

	Fs.readFile filePath, (err, buffer) ->
		if err
			if err.code is 'EISDIR'
				console.warn "Skipping directory: '#{filePath}'"
				cb()
				return

			cb err
			return

		fileData = JSON.parse globalEncryptionKey.decrypt buffer
		cb null, Imm.fromJS(fileData)

getAllRevisions = (dirPath, globalEncryptionKey, cb) ->
	console.log "Getting all revisions in #{dirPath}"

	filesList = null
	revisions = null

	Async.series [
		(cb) ->
			console.log "dirPath", dirPath
			Fs.readdir dirPath, (err, result) ->
				if err
					if err.code is 'ENOENT'
						console.error "'#{dirPath}' does exist.", err						
					cb err
					return

				filesList = result
				cb()

		(cb) ->
			Async.map filesList, (file, cb) ->
				console.log "Reading #{file}"

				filePath = Path.join(dirPath, file)
				readFileData filePath, globalEncryptionKey, cb
			, (err, results) ->
				if err
					cb err
					return

				revisions = Imm.List(results)
				.filter (result) -> result? # Strip out folders (undefined)
				.sortBy (result) -> Moment(result.get('timestamp'), TimestampFormat)

				cb()

	], (err) ->
		if err
			cb err
			return

		cb null, revisions

getLatestRevision = (dirPath, globalEncryptionKey, cb) ->
	console.log "Getting latest revision for #{dirPath}"
	getAllRevisions dirPath, globalEncryptionKey, (err, results) ->
		if err
			cb err
			return

		latestRevision = results.last()
		cb null, latestRevision


# //////////////// Version-Specific Utilities /////////////////


addContextFieldsToAllObjects = (dataDir, globalEncryptionKey, cb) ->
	Async.series [
		(cb) ->
			forEachFile Path.join(dataDir, 'clientFiles'), (clientFile, cb) ->
				clientFilePath = Path.join(dataDir, 'clientFiles', clientFile)

				forEachFile clientFilePath, (clientFileRev, cb) ->
					if clientFileRev is 'planTargets'
						forEachFile Path.join(clientFilePath, 'planTargets'), (planTarget, cb) ->
							planTargetPath = Path.join(clientFilePath, 'planTargets', planTarget)

							forEachFile planTargetPath, (planTargetRev, cb) ->
								objPath = Path.join(planTargetPath, planTargetRev)

								addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
							, cb
						, cb
						return

					if clientFileRev is 'progEvents'
						forEachFile Path.join(clientFilePath, 'progEvents'), (progEvent, cb) ->
							progEventPath = Path.join(clientFilePath, 'progEvents', progEvent)

							forEachFile progEventPath, (progEventRev, cb) ->
								objPath = Path.join(progEventPath, progEventRev)

								addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
							, cb
						, cb
						return

					if clientFileRev is 'progNotes'
						forEachFile Path.join(clientFilePath, 'progNotes'), (progNote, cb) ->
							progNotePath = Path.join(clientFilePath, 'progNotes', progNote)

							forEachFile progNotePath, (progNoteRev, cb) ->
								objPath = Path.join(progNotePath, progNoteRev)

								addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
							, cb
						, cb
						return

					objPath = Path.join(clientFilePath, clientFileRev)

					addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
				, cb
			, cb
		(cb) ->
			forEachFile Path.join(dataDir, 'metrics'), (metric, cb) ->
				metricPath = Path.join(dataDir, 'metrics', metric)

				forEachFile metricPath, (metricRev, cb) ->
					objPath = Path.join(metricPath, metricRev)

					addContextFieldsToObject objPath, dataDir, globalEncryptionKey, cb
				, cb
			, cb
	], cb

addContextFieldsToObject = (objFilePath, dataDir, globalEncryptionKey, cb) ->
	# Figure out the object's context
	objDir = Path.relative(dataDir, Path.dirname objFilePath)
	objDirParts = objDir.split(Path.sep)

	Assert objDirParts.length % 2 is 0, "even number of parent dirs needed"

	objCollectionName = objDirParts[objDirParts.length - 2]
	objContextDirParts = objDirParts[...-2]

	# Extract context information from the file path
	contextCollectionNames = []
	contextIds = []
	for objDirPart, i in objContextDirParts
		if i % 2 is 0
			contextCollectionNames.push objDirPart
		else
			indexedFields = objDirPart.split('.')
			objId = indexedFields[indexedFields.length - 1]
			contextIds.push objId

	obj = null

	Async.series [
		(cb) ->
			Fs.readFile objFilePath, (err, result) ->
				if err
					cb err
					return

				obj = JSON.parse globalEncryptionKey.decrypt result
				cb()
		(cb) ->
			obj._collectionName = objCollectionName
			obj._contextCollectionNames = contextCollectionNames
			obj._contextIds = contextIds

			encryptedObj = globalEncryptionKey.encrypt JSON.stringify obj

			Fs.writeFile objFilePath, encryptedObj, cb
	], cb


groupPlanTargetsIntoSections = (progNoteUnit, cb) ->

	Async.series [
		# 2a. Read the progNote revision
		(cb) ->
			console.log "Getting progNote revision: #{progNoteRevisionPath}"

			readFileData progNoteRevisionPath, globalEncryptionKey, (err, result) ->
				if err
					cb err
					return

				progNote = result
				console.info "progNote", progNote.toJS()

				isFullProgNoteUnit = progNote.get('type') is 'full'
				unless isFullProgNoteUnit
					console.warn "Not a 'plan' progNote unit, skipping remainder..."

				cb()

		# 2b. Change the high-level property 'sections' to 'units'
		(cb) ->
			cb() unless isFullProgNoteUnit

			console.log "Changing high-level progNote property 'sections' to 'units'"

			progNote = progNote.mapKeys (key) -> 
				switch key
					when 'sections'
						console.log "Changing key name 'sections' to 'units'"
						return 'units'
					when 'units'
						console.warn "progNote already has 'sections' named as 'units'"
						return key
					else
						return key

			console.info "progNote with units", progNote.toJS()
			cb()

		# 2c. Extract targets from each 'unit'
		(cb) ->
			cb() unless isFullProgNoteUnit

			console.log "Extracting units"

			unless progNote.get('units')?
				console.warn "progNote doesn't have units", progNote.toJS()

			progNoteUnits = progNote.get('units')

			console.info "progNoteUnits", progNoteUnits

			# progNoteUnits = progNoteUnits.map (unit) ->
			# 	if unit.get('type') isnt 'plan'
			# 		console.warn "Skipping unit because type: #{unit.get 'type'}"
			# 		return unit

			# 	if unit.has('sections')
			# 		console.warn "Skipping unit because already has 'sections'"

			# 	planSections = clientFilePlan.get('sections')
			# 	console.log "planSections", planSections
			# 	return

				

			console.info "NEW progNoteUnits", progNoteUnits
			# .filter (unit) -> unit.get('type') is 'plan'

			# fullProgNotes = Imm.List(
			# 	progNote.get('units').filter (unit) -> unit.get('type') is 'plan'
			# )

			# console.info "fullProgNotes", fullProgNotes, fullProgNotes.toJS()
			cb()

	], cb


# ////////////////////// Migration Series //////////////////////

module.exports = {
	run: (dataDir, userName, password, cb) ->
		globalEncryptionKey = null

		Async.series [
			
			# Global Encryption Key
			(cb) ->				
				loadGlobalEncryptionKey dataDir, userName, password, (err, result) ->
					if err
						cb err
						return

					globalEncryptionKey = result
					cb()

			# Add Context Fields to all objects
			(cb) ->				
				addContextFieldsToAllObjects dataDir, globalEncryptionKey, cb

			# New Directory: 'programs'
			(cb) ->
				console.info "About to start adding directories..."
				createEmptyDirectory dataDir, 'programs', cb

			# New Directory: 'clientFileProgramLinks'
			(cb) ->				
				createEmptyDirectory dataDir, 'clientFileProgramLinks', cb

			# Improvements for progNote Schema (issue#7)
			# A -> top-level prop name 'sections' changed to 'units'
			# B -> unit/type:full/type:plan/targets changed to array of 'sections'
			# 	-> 'sections' relationships are mapped over from 'plan' construct
			(cb) ->
				# Loop through clientFiles
				forEachFile Path.join(dataDir, 'clientFiles'), (clientFileDir, cb) ->
					clientFileDirPath = Path.join(dataDir, 'clientFiles', clientFileDir)

					clientFilePlan = null

					Async.series [
						# 1. Get 'plan' from latest revision of clientFile
						(cb) ->
							console.log "Getting 'plan'"							

							getLatestRevision clientFileDirPath, globalEncryptionKey, (err, revision) ->
								if err
									cb err
									return

								console.info "Latest Revision", revision
								clientFilePlan = revision.get('plan')
								cb()

						# 2. Get all progNotes
						(cb) ->
							console.log "Getting all progNotes"
							progNotesParentDirPath = Path.join(clientFileDirPath, 'progNotes')

							# Loop through directories in progNotes container
							forEachFile progNotesParentDirPath, (progNotesDir, cb) ->
								progNotesDirPath = Path.join(progNotesParentDirPath, progNotesDir)

								console.info "Looking into progNoteDir #{progNotesDirPath}"

								# Loop through each progNote revision
								forEachFile progNotesDirPath, (progNoteRevision, cb) ->
									progNoteRevisionPath = Path.join(progNotesDirPath, progNoteRevision)

									progNote = null
									isFullProgNoteUnit = null
									planTargets = null


									console.log "Getting progNote revision: #{progNoteRevisionPath}"

									# Read progNote
									readFileData progNoteRevisionPath, globalEncryptionKey, (err, result) ->
										if err
											cb err
											return

										progNote = result
										console.info "progNote", progNote.toJS()

										# Quick Notes aren't applicable, skip!
										if progNote.get('type') isnt 'full'
											console.log "Skipping 'basic' progNote (Quick Note)"
											cb()
											return

										# Change keyName 'sections' to 'units'
										progNote = result.mapKeys (key) -> 
											switch key
												when 'sections'
													console.log "Changing key name 'sections' to 'units'"
													return 'units'
												when 'units'
													console.warn "progNote already has 'sections' named as 'units'"
													return key
												else
													return key

										console.info "progNote with new key name:", progNote.toJS()

										# Map units over to the new format
										# -> targets mapped into appropriate sections
										newUnits = progNote.get('units').map (unit) ->
											if not unit.has('sections') and unit.get('targets')?

												# Use clientFilePlan sections as our template
												unitPlanSections = clientFilePlan.get('sections').map (planSection) ->
													console.info "planSection", planSection.toJS()

													relatedTargets = Imm.List()
													unit.get('targets').forEach (target) ->
														if planSection.get('targetIds').contains target.get('id')
															relatedTargets = relatedTargets.push target

													console.info "relatedTargets", relatedTargets.toJS()

													# Return a planSection as a unitPlanSection w/ targets
													return planSection
													.delete('targetIds')
													.set('targets', relatedTargets)

												console.info "NEW unitPlanSections", unitPlanSections

												# Return unit with new 'sections' property
												return unit
												.delete('targets')
												.set('sections', unitPlanSections)

											else
												console.warn "progNote unit already has 'sections':", unit.toJS()
												return unit

										console.info "newUnits:", newUnits.toJS()
										
										cb()

								, cb
							, cb

					], cb
				, cb

		], cb
}