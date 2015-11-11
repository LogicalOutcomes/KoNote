Async = require 'async'
Base64url = require 'base64url'
Fs = require 'fs'
Imm = require 'immutable'
Path = require 'path'

{SymmetricEncryptionKey, PrivateKey, PublicKey} = require '../persist/crypto'

module.exports = {

	run: (dataDir, userName, password, cb) ->
		adminKdfParams = null
		adminPwEncryptionKey = null
		adminPrivateKeys = null

		userNames = null
		systemUserDir = Path.join(dataDir, '_users', '_system')
		weakSystemKey = null

		Async.series [
			(cb) ->
				console.log "Reading admin's auth-params"
				Fs.readFile Path.join(dataDir, '_users', userName, 'auth-params'), (err, result) ->
					if err
						cb err
						return

					adminKdfParams = JSON.parse result
					cb()
			(cb) ->
				console.log "Deriving key from admin password"
				SymmetricEncryptionKey.derive password, adminKdfParams, (err, result) ->
					if err
						cb err
						return

					adminPwEncryptionKey = result
					cb()
			(cb) ->
				console.log "Reading admin private keys"
				Fs.readFile Path.join(dataDir, '_users', userName, 'private-keys'), (err, result) ->
					if err
						cb err
						return

					adminPrivateKeys = JSON.parse adminPwEncryptionKey.decrypt result
					cb()
			(cb) ->
				console.log "Listing _users dir"
				Fs.readdir Path.join(dataDir, '_users'), (err, result) ->
					if err
						cb err
						return

					userNames = result
					cb()
			(cb) ->
				console.log "Generating system key"
				PrivateKey.generate (err, result) ->
					if err
						cb err
						return

					weakSystemKey = result
					cb()
			(cb) ->
				console.log "Creating system user dir"
				Fs.mkdir systemUserDir, cb
			(cb) ->
				console.log "Writing system public key"
				publicKeyPath = Path.join(systemUserDir, 'public-key')

				Fs.writeFile publicKeyPath, weakSystemKey.getPublicKey().export(), cb
			(cb) ->
				console.log "Writing old-key"
				privateKeyPath = Path.join(systemUserDir, 'old-key')
				globalEncryptionKey = SymmetricEncryptionKey.import(
					adminPrivateKeys.globalEncryptionKey
				)
				encryptedSystemKey = globalEncryptionKey.encrypt(weakSystemKey.export())

				# Temporary workaround: make the system key public until
				# all accounts are migrated to the new key escrow scheme.
				# Then the system key can be regenerated and kept private.
				Fs.writeFile privateKeyPath, encryptedSystemKey, cb
			(cb) ->
				console.log "Upgrading user accounts:"
				Async.eachSeries userNames, (userName, cb) ->
					userDir = Path.join(dataDir, '_users', userName)
					publicInfo = {isActive: true}

					console.log " - #{userDir}"

					Async.series [
						(cb) ->
							Fs.readFile Path.join(userDir, 'account-type'), (err, buf) ->
								if err
									cb err
									return

								publicInfo.accountType = JSON.parse buf
								cb()
						(cb) ->
							publicInfoPath = Path.join(userDir, 'public-info')

							Fs.writeFile publicInfoPath, JSON.stringify(publicInfo), cb
						(cb) ->
							Fs.unlink Path.join(userDir, 'account-type'), cb
					], cb
				, cb
		], cb

}