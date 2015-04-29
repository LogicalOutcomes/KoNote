Assert = require 'assert'
Async = require 'async'

{SymmetricEncryptionKey} = require '../../persist/crypto'

describe 'SymmetricEncryptionKey', ->
	it 'prevents accidental instantiation', ->
		Assert.throws ->
			new SymmetricEncryptionKey(new Buffer(32))

	it 'generates unique keys', ->
		k1 = SymmetricEncryptionKey.generate()
		k2 = SymmetricEncryptionKey.generate()
		Assert.notStrictEqual k1._rawKeyMaterial, k2._rawKeyMaterial

	it 'derives different keys for different passwords', (cb) ->
		Async.parallel [
			(cb) ->
				SymmetricEncryptionKey.derive 'password', 'nacl', cb
			(cb) ->
				SymmetricEncryptionKey.derive 'pass', 'nacl', cb
		], (err, keys) ->
			if err then throw err

			Assert not keys[0]._rawKeyMaterial.equals keys[1]._rawKeyMaterial
			cb()

	it 'derives different keys for different salts', (cb) ->
		Async.parallel [
			(cb) ->
				SymmetricEncryptionKey.derive 'pass', 'nacl1', cb
			(cb) ->
				SymmetricEncryptionKey.derive 'pass', 'nacl2', cb
		], (err, keys) ->
			if err then throw err

			Assert not keys[0]._rawKeyMaterial.equals keys[1]._rawKeyMaterial
			cb()

	it 'derives the same key for buffer vs string', (cb) ->
		Async.parallel [
			(cb) ->
				SymmetricEncryptionKey.derive 'pass', 'nacl', cb
			(cb) ->
				SymmetricEncryptionKey.derive 'pass', new Buffer('nacl', 'utf8'), cb
		], (err, keys) ->
			if err then throw err

			Assert keys[0]._rawKeyMaterial.equals keys[1]._rawKeyMaterial
			cb()

	it 'imports keys from hex', ->
		keyText = 'symmkey-v1:abcdabcd12341234abcdabcd12341234abcdabcd12341234abcdabcd12341234'
		k = SymmetricEncryptionKey.import keyText
		Assert k

	it 'does not import keys with the wrong length', ->
		keyText = 'symmkey-v1:abcd'
		Assert.throws ->
			SymmetricEncryptionKey.import keyText

	it 'does not import keys from a different protocol version', ->
		keyText = 'symmkey-v2:abcdabcd12341234abcdabcd12341234abcdabcd12341234abcdabcd12341234'
		Assert.throws ->
			SymmetricEncryptionKey.import keyText

	it 'can export and import a key', ->
		k = SymmetricEncryptionKey.generate()
		keyText = k.export()
		k2 = SymmetricEncryptionKey.import(keyText)
		Assert k._rawKeyMaterial.equals k2._rawKeyMaterial

	it 'encrypts data with 33 bytes of overhead', ->
		myData = 'hello, world!'
		k = SymmetricEncryptionKey.generate()
		ct = k.encrypt myData
		Assert.strictEqual ct.length, myData.length + 33

		k2 = SymmetricEncryptionKey.import k.export()
		pt = k2.decrypt ct
		Assert.strictEqual pt.toString('utf8'), myData

	it 'refuses to decrypt an invalid auth tag', ->
		myData = 'hey there, world'
		k = SymmetricEncryptionKey.generate()
		ct = k.encrypt myData

		# Flip the bits of the last byte
		ct[ct.length - 1] = ct[ct.length - 1] ^ 0xFF

		Assert.throws ->
			pt = k2.decrypt ct

	it 'refuses to decrypt tampered data', ->
		myData = 'hey there, world'
		k = SymmetricEncryptionKey.generate()
		ct = k.encrypt myData

		# Flip the bits of a ciphertext byte
		ct[18] = ct[18] ^ 0xFF

		Assert.throws ->
			pt = k2.decrypt ct

	it 'refuses to decrypt with the wrong key', ->
		k1 = SymmetricEncryptionKey.generate()
		k2 = SymmetricEncryptionKey.generate()
		ct = k1.encrypt 'test'

		Assert.throws ->
			pt = k2.decrypt ct
