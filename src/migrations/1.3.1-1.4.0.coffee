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
								
								cb()
						(cb) =>
							console.log "Read each progNote directory"

							# Loop through progNote directories
							Async.eachSeries progNoteDirs, (progNote, cb) ->					

								progNoteFiles = null
								progNoteFilePath = null
								progNoteFolders = null

								progNoteDir = Path.join(progNotesDir, progNote)

								Async.series [
									(cb) =>
										console.log "About to read progNote dir...."

										# Read the names of progNote folders
										Fs.readdir progNoteDir, (err, result) ->
											if err
												cb err
												return

											progNoteFiles = result
											cb()
									(cb) =>
										console.log "About to loop through progNote files, which are: ", progNoteFiles

										# Loop through each progNote file
										Async.eachSeries progNoteFiles, (progNoteFile, cb) ->

											progNoteFilePath = Path.join(progNoteDir, progNoteFile)

											newBuf = null

											# Read and write progNote file and its directory
											Async.series [
												(cb) ->
													# Read file, add blank backdate
													Fs.readFile progNoteFilePath, (err, buf) ->
														if err
															cb err
															return
														note = JSON.parse globalEncryptionKey.decrypt buf
														note.backdate = ''
														newBuf = globalEncryptionKey.encrypt JSON.stringify note
														cb()
												(cb) ->
													# Write file 
													Fs.writeFile progNoteFilePath, newBuf, (err) ->
														if err
															cb err
															return
														cb()
												(cb) ->
													# Rename parent directory with empty index
													tempProgNote = progNote.replace(".", "..")
													newProgNoteDir = Path.join(progNotesDir, tempProgNote)
													
													Fs.rename progNoteDir, newProgNoteDir, (err) ->
														if err
															cb err
															console.error "Error renaming directory: ", err
															return

														console.log "Rewrote folder and file for progNote:", progNoteFile
														cb()
											], cb

										, cb
								], cb
							, cb
					], cb
				, cb
		], cb

}
