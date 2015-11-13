Async = require 'async'
Base64url = require 'base64url'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'

{SymmetricEncryptionKey, PrivateKey, PublicKey} = require '../persist/crypto'

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

					cb new IOError err
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
					cb new IOError err
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
					cb new IOError err
					return

				privateInfo = JSON.parse accountKey.decrypt buf
				cb()
	], (err) =>
		if err
			cb err
			return

		globalEncryptionKey = SymmetricEncryptionKey.import privateInfo.globalEncryptionKey
		cb null, globalEncryptionKey


module.exports = {

	run: (dataDir, userName, password, cb) ->

		globalEncryptionKey = null
		clientFiles = null
		clientFileDirs = null

		Async.series [
			(cb) ->
				loadGlobalEncryptionKey dataDir, userName, password, (err, result) ->
					if err
						cb err
						return

					globalEncryptionKey = result
					cb()
			(cb) ->
				console.log "Listing clientFiles dir"
				Fs.readdir Path.join(dataDir, 'clientFiles'), (err, result) ->
					if err
						cb err
						return

					clientFileDirs = result
					console.log "clientFileDirs", clientFileDirs
					cb()
			(cb) ->
				console.log "About to loop through each clientFile dir"

				Async.eachSeries clientFileDirs, (clientFile, cb) ->
					progNotesDir = Path.join(dataDir, 'clientFiles', clientFile, 'progNotes')

					console.info " - #{clientFile}"
					progNoteDirs = null

					Async.series [
						# Get list of progNote directories
						(cb) =>
							console.log "Listing progNotes directories"

							Fs.readdir progNotesDir, (err, result) ->
								if err
									cb err
									return

								progNoteDirs = result
								console.log "progNoteDirs", progNoteDirs
								
								cb()
						(cb) =>
							console.log "Read each progNote directory"

							# Loop through progNote directories
							Async.eachSeries progNoteDirs, (progNote, cb) ->					

								progNoteFiles = null
								progNoteFilePath = null
								progNoteFolders = null

								progNoteDir = Path.join(progNotesDir, progNote)
								console.log "Added directory name to path + ", progNote

								console.log "progNoteDir", progNoteDir

								Async.series [
									(cb) =>
										console.log "About to read progNote dir...."
										# Read the names of progNote folders
										Fs.readdir progNoteDir, (err, result) ->
											if err
												cb err
												return

											progNoteFiles = result
											# console.log "progNoteFiles", progNoteFiles
											cb()
									(cb) =>
										console.log "About to loop through progNote files, which are: ", progNoteFiles

										# Check to see if there's only 1 progNoteFile, deliver error if > 1 or 0
										
										if progNoteFiles.length is not 1
											console.log "error, expect 1 prognote per directory. are you sure you are migrating from 1.3.1?"
											return

										# Loop through each progNote file
										Async.eachSeries progNoteFiles, (progNoteFile, cb) ->

											progNoteFilePath = Path.join(progNoteDir, progNoteFile)

											console.log "progNoteFilePath : : ", progNoteFilePath
											
											newBuf = null

											# Read and write file!
											Async.series [
												(cb) ->
													# read file
													Fs.readFile progNoteFilePath, (err, buf) ->
														if err
															cb new IOError err
															return
														note = JSON.parse globalEncryptionKey.decrypt buf
														console.log "backdate: ", note.backdate

														note.backdate = ''

														newBuf = globalEncryptionKey.encrypt JSON.stringify note
														cb()
												(cb) ->
													#write file 
													Fs.writeFile progNoteFilePath, newBuf, (err) ->
														if err
															cb new IOError err
															return
														console.log "file saved"
														cb()
												(cb) ->
													# rename directory (add index)

													console.log "prognote folder: ", progNote
													console.log "prognote parent folder: ", progNotesDir
													
													tempProgNote = progNote.replace(".", "..")
													
													newProgNoteDir = Path.join(progNotesDir, tempProgNote)
													
													#progNoteParent = progNotesDir
													#newProgNoteDir = tempProgNoteDir.splice(-1, '')
													#console.log "new dir: ", newProgNoteDir
													#newProgNotePath = newProgNoteDir.join
													
													
													Fs.rename progNoteDir, newProgNoteDir, (err) ->
														if err
															cb err
															console.log "Error renaming directory: ", err
															return
														console.log "directory renamed"
														cb()
											], cb

											# obj = JSON.parse globalEncryptionKey.decrypt result
											# obj.backdate = ''
											# newBuf = globalEncryptionKey.encrypt JSON.stringify obj
											# save
											# {}
										, cb
								], cb
							, cb
					], cb
				, cb
		], cb

}
