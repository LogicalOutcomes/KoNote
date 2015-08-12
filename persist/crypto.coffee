# This module defines all cryptographic operations (encryption, digital
# signatures, etc) used in this project.
#
# WARNING: This code is delicate.  I strongly recommend avoiding changing this
# code if possible.  Ask Tim McLean <tim@timmclean.net> to review any and all
# changes, even refactors.

BufferEq = require 'buffer-equal-constant-time'
Crypto = require 'crypto'

keyTextV1Prefix = 'symmkey-v1'
cipherTextV1Prefix = new Buffer([1])

class SymmetricEncryptionKey
	# Implementation notes:
	# - Key derivation using PBKDF2-SHA256 with a 32-byte output
	# - Both encrypted messages and exported keys include version number in
	#   case versioning scheme is needed in future
	# - Encryption performed with AES256-GCM

	# PRIVATE CONSTRUCTOR
	# Do not call this directly.
	# Use generate, derive, or import instead.
	constructor: (rawKeyMaterial, check) ->
		unless check is 'iknowwhatimdoing'
			# This is to prevent accidental usage of this constructor outside of this class.
			throw new Error "Use SymmetricEncryptionKey.generate, .derive, or .import instead"

		unless Buffer.isBuffer rawKeyMaterial
			throw new Error "expected rawKeyMaterial to be a Buffer"

		@_rawKeyMaterial = rawKeyMaterial

	# Generate a new encryption key
	@generate: ->
		keyMat = Crypto.randomBytes(32) # suitable for AES256
		return new SymmetricEncryptionKey(keyMat, 'iknowwhatimdoing')

	# Convert a password into an encryption key
	# `params` should be saved somewhere public.
	#
	# To generate params the first time:
	#   params = {salt: generateSalt(), iterationCount: 500000}
	#
	# iterationCount is the security level: higher means safer but slower.
	@derive: (password, params, cb) ->
		unless typeof password is 'string'
			# Note: it's probably not safe to pass in arbitrary binary as a password
			cb new Error "password must be a string"
			return

		unless params.iterationCount
			cb new Error "key derivation params must contain an iteration count"
			return

		unless params.salt
			cb new Error "key derivation params must contain a salt, see generateSalt"
			return

		iterationCount = +params.iterationCount
		salt = params.salt

		Crypto.pbkdf2 password, salt, iterationCount, 32, 'sha256', (err, keyMat) ->
			if err
				cb err
				return

			key = new SymmetricEncryptionKey(keyMat, 'iknowwhatimdoing')
			cb null, key

	# Import an existing encryption key
	@import: (keyText) ->
		if typeof keyText isnt 'string'
			throw new Error "expected keyText to be a string"

		[prefix, keyMatHex] = keyText.split ':'

		unless prefix is keyTextV1Prefix
			throw new Error "error while importing encryption key"

		keyMat = new Buffer(keyMatHex, 'hex')

		if keyMat.length isnt 32
			throw new Error "key is wrong length"

		return new SymmetricEncryptionKey(keyMat, 'iknowwhatimdoing')

	# Convert this key to a text format so that it can be saved somewhere
	export: ->
		return [keyTextV1Prefix, @_rawKeyMaterial.toString('hex')].join ':'

	# Encrypt the provided string or Buffer
	encrypt: (msg) ->
		if typeof msg is 'string'
			msg = new Buffer(msg, 'utf8')

		unless Buffer.isBuffer msg
			throw new Error "expected msg to be a string or Buffer"

		outputBuffers = []

		# Future-proof with a version identifier
		outputBuffers.push cipherTextV1Prefix

		# Add length field
		lenField = new Buffer(4)
		lenField.writeUInt32LE 12 + msg.length + 16
		outputBuffers.push lenField

		iv = Crypto.randomBytes(12)
		outputBuffers.push iv
		cipher = Crypto.createCipheriv('aes-256-gcm', @_rawKeyMaterial, iv)
		outputBuffers.push cipher.update(msg)
		outputBuffers.push cipher.final()
		outputBuffers.push cipher.getAuthTag()

		return Buffer.concat outputBuffers

	# Decrypt the provided Buffer
	decrypt: (encryptedMsg) ->
		unless Buffer.isBuffer encryptedMsg
			throw new Error "expected encryptedMsg to be a Buffer"

		prefix = encryptedMsg[...cipherTextV1Prefix.length]
		unless BufferEq(prefix, cipherTextV1Prefix)
			throw new Error "unknown encryption version"

		gcmLen = encryptedMsg.readUInt32LE cipherTextV1Prefix.length

		if gcmLen < (12 + 16)
			throw new Error "encrypted data is too short"

		gcmPart = encryptedMsg.slice cipherTextV1Prefix.length + 4

		if gcmPart.length isnt gcmLen
			throw new Error "expected #{gcmLen} bytes but found #{gcmPart.length} bytes"

		iv = gcmPart[...12]
		ciphertext = gcmPart[12...-16]
		authTag = gcmPart[-16...]

		decipher = Crypto.createDecipheriv('aes-256-gcm', @_rawKeyMaterial, iv)
		decipher.setAuthTag authTag

		return Buffer.concat [
			decipher.update(ciphertext)
			decipher.final()
		]

	# Wipe the key from memory.  A key object should not be used after being
	# erased (it will fail).
	erase: ->
		@_rawKeyMaterial.fill(0)
		@_rawKeyMaterial = null

generateSalt = ->
	return Crypto.randomBytes(16).toString('hex')

module.exports = {SymmetricEncryptionKey, generateSalt}
