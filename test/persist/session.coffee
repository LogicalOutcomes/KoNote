Assert = require 'assert'
Async = require 'async'
Fs = require 'fs'
Mkdirp = require 'mkdirp'
Path = require 'path'
Rimraf = require 'rimraf'

{
	SymmetricEncryptionKey
} = require '../../persist/crypto'

{
	login
	UnknownUserNameError
	IncorrectPasswordError
} = require '../../persist/session'

describe 'Session', ->
	dataDir = Path.join process.cwd(), 'testData'

	describe '.login', ->
		before (cb) ->
			Rimraf dataDir, cb

		# Set up the user account files before each test
		beforeEach (cb) ->
			userDir = Path.join(dataDir, '_users', 'testuser')
			Mkdirp userDir, (err) ->
				if err
					cb err
					return

				authParams = {
					iterationCount: 1
					salt: 'nacl'
				}
				Fs.writeFileSync Path.join(userDir, 'auth-params'), JSON.stringify(authParams)

				accountType = "normal"
				Fs.writeFileSync Path.join(userDir, 'account-type'), JSON.stringify(accountType)

				SymmetricEncryptionKey.derive 'pass', authParams, (err, userKey) ->
					if err
						cb err
						return

					privKeys = {
						globalEncryptionKey: SymmetricEncryptionKey.generate().export()
					}
					privKeysFile = userKey.encrypt JSON.stringify privKeys
					Fs.writeFileSync Path.join(userDir, 'private-keys'), privKeysFile
					cb()

		afterEach (cb) ->
			Rimraf dataDir, cb

		it 'throws UnknownUserNameError if user name unknown', (cb) ->
			login dataDir, 'invaliduser', 'pass', (err, result) ->
				Assert err instanceof UnknownUserNameError
				cb()

		it 'throws IncorrectPasswordError if password wrong', (cb) ->
			login dataDir, 'testuser', 'password', (err, result) ->
				Assert err instanceof IncorrectPasswordError
				cb()

		it 'starts a login session if credentials are valid', (cb) ->
			login dataDir, 'testuser', 'pass', (err, result) ->
				Assert.strictEqual err, null
				Assert result
				cb()
