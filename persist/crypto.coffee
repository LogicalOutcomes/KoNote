# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module defines all cryptographic operations (encryption, digital
# signatures, etc) used in this project.
#
# WARNING: This code is delicate.  I strongly recommend avoiding changing this
# code if possible.  Ask Tim McLean <tim@timmclean.net> to review any and all
# changes, even refactors.

Async = require 'async'
Base64url = require 'base64url'
BufferEq = require 'buffer-equal-constant-time'
Crypto = require 'crypto'

symmKeyV1Prefix = 'symmkey-v1'
symmCiphertextV1Prefix = new Buffer([1])

privKeyV1Prefix = 'privkey-v1'
pubKeyV1Prefix = 'pubkey-v1'
asymmCiphertextV1Prefix = new Buffer([1])

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

		unless prefix is symmKeyV1Prefix
			throw new Error "error while importing encryption key"

		keyMat = new Buffer(keyMatHex, 'hex')

		if keyMat.length isnt 32
			throw new Error "key is wrong length"

		return new SymmetricEncryptionKey(keyMat, 'iknowwhatimdoing')

	# Convert this key to a text format so that it can be saved somewhere
	export: ->
		return [symmKeyV1Prefix, @_rawKeyMaterial.toString('hex')].join ':'

	# Encrypt the provided string or Buffer
	encrypt: (msg) ->
		if typeof msg is 'string'
			msg = new Buffer(msg, 'utf8')

		unless Buffer.isBuffer msg
			throw new Error "expected msg to be a string or Buffer"

		outputBuffers = []

		# Future-proof with a version identifier
		outputBuffers.push symmCiphertextV1Prefix

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

		prefix = encryptedMsg[...symmCiphertextV1Prefix.length]
		unless BufferEq(prefix, symmCiphertextV1Prefix)
			throw new Error "unknown encryption version"

		gcmLen = encryptedMsg.readUInt32LE symmCiphertextV1Prefix.length

		if gcmLen < (12 + 16)
			throw new Error "encrypted data is too short"

		gcmPart = encryptedMsg.slice symmCiphertextV1Prefix.length + 4

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

# TODO move this somewhere else
usePromise = (promise, cb) ->
	promise.catch (err) ->
		cb err
	promise.then (args...) ->
		cb null, args...

toPemKeyFormat = (fileType, buf) ->
	result = ''

	result += "-----BEGIN #{fileType}-----\n"

	b64Data = buf.toString('base64')
	lineLength = 64
	for lineIndex in [0...Math.ceil(b64Data.length/lineLength)]
		line = b64Data[(lineLength * lineIndex)...(lineLength * (lineIndex + 1))]
		result += line
		result += '\n'

	result += "-----END #{fileType}-----\n"

	return result

# TODO security review still needed for PrivateKey and PublicKey
class PrivateKey
	# PRIVATE CONSTRUCTOR
	# Do not call this directly.
	# Use generate or import instead.
	constructor: (rawPrivEncrKey, rawPubEncrKey, rawPrivSignKey, rawPubSignKey, check) ->
		unless check is 'iknowwhatimdoing'
			# This is to prevent accidental usage of this constructor outside of this class.
			throw new Error "Use PrivateKey.generate or .import instead"

		unless Buffer.isBuffer rawPrivEncrKey
			throw new Error "expected rawPrivEncrKey to be a Buffer"

		unless Buffer.isBuffer rawPubEncrKey
			throw new Error "expected rawPubEncrKey to be a Buffer"

		unless Buffer.isBuffer rawPrivSignKey
			throw new Error "expected rawPrivSignKey to be a Buffer"

		unless Buffer.isBuffer rawPubSignKey
			throw new Error "expected rawPubSignKey to be a Buffer"

		@_rawPrivEncrKey = rawPrivEncrKey
		@_rawPubEncrKey = rawPubEncrKey
		@_rawPrivSignKey = rawPrivSignKey
		@_rawPubSignKey = rawPubSignKey

	@generate: (cb) ->
		webCryptoApi = global.window.crypto.subtle

		privEncrKey = null
		pubEncrKey = null
		privSignKey = null
		pubSignKey = null

		Async.series [
			(cb) ->
				usePromise webCryptoApi.generateKey(
					{
						name: 'RSA-OAEP'
						modulusLength: 3072
						publicExponent: new Uint8Array([1, 0, 1]) # 65537
						hash: 'SHA-256'
					},
					true, # extractable
					['encrypt', 'decrypt']
				), (err, keyPair) ->
					if err
						cb err
						return

					privEncrKey = keyPair.privateKey
					pubEncrKey = keyPair.publicKey
					cb()
			(cb) ->
				usePromise webCryptoApi.generateKey(
					{
						name: 'RSASSA-PKCS1-v1_5'
						modulusLength: 3072
						publicExponent: new Uint8Array([1, 0, 1]) # 65537
						hash: 'SHA-256'
					},
					true, # extractable
					['sign', 'verify']
				), (err, keyPair) ->
					if err
						cb err
						return

					privSignKey = keyPair.privateKey
					pubSignKey = keyPair.publicKey
					cb()
			(cb) ->
				Async.map [
					[privEncrKey, 'pkcs8']
					[pubEncrKey, 'spki']
					[privSignKey, 'pkcs8']
					[pubSignKey, 'spki']
				], ([key, format], cb) ->
					usePromise webCryptoApi.exportKey(format, key), (err, exportedKeyBuf) ->
						if err
							cb err
							return

						uint8s = new Uint8Array(exportedKeyBuf)
						result = new Buffer(uint8s.length)

						for i in [0...result.length]
							result[i] = uint8s[i]

						cb null, result
				, (err, results) ->
					if err
						cb err
						return

					privEncrKey = results[0]
					pubEncrKey = results[1]
					privSignKey = results[2]
					pubSignKey = results[3]
					cb()
		], (err) ->
			if err
				cb err
				return

			cb null, new PrivateKey(
				privEncrKey, pubEncrKey,
				privSignKey, pubSignKey,
				'iknowwhatimdoing'
			)

	@import: (keyText) ->
		if typeof keyText isnt 'string'
			throw new Error "expected keyText to be a string"

		[
			prefix,
			privEncrKeyB64, pubEncrKeyB64,
			privSignKeyB64, pubSignKeyB64,
		] = keyText.split ':'

		unless prefix is privKeyV1Prefix
			throw new Error "error while importing private key"

		return new PrivateKey(
			Base64url.toBuffer(privEncrKeyB64),
			Base64url.toBuffer(pubEncrKeyB64),
			Base64url.toBuffer(privSignKeyB64),
			Base64url.toBuffer(pubSignKeyB64),
			'iknowwhatimdoing'
		)

	export: ->
		return [
			privKeyV1Prefix,
			Base64url.encode(@_rawPrivEncrKey),
			Base64url.encode(@_rawPubEncrKey),
			Base64url.encode(@_rawPrivSignKey),
			Base64url.encode(@_rawPubSignKey)
		].join ':'

	getPublicKey: ->
		return new PublicKey(@_rawPubEncrKey, @_rawPubSignKey, 'iknowwhatimdoing')

	decrypt: (encryptedMsg) ->
		unless Buffer.isBuffer encryptedMsg
			throw new Error "expected encryptedMsg to be a Buffer"

		prefix = encryptedMsg[...asymmCiphertextV1Prefix.length]
		unless BufferEq(prefix, asymmCiphertextV1Prefix)
			throw new Error "unknown encryption version"

		# next 512 bytes (4096 bits)
		encryptedContentKey =
			encryptedMsg[asymmCiphertextV1Prefix.length...(asymmCiphertextV1Prefix.length + 512)]

		contentKeyText = Crypto.privateDecrypt(
			toPemKeyFormat('PRIVATE KEY', @_rawPrivEncrKey),
			encryptedContentKey
		)
		contentKey = SymmetricEncryptionKey.import(contentKeyText.toString())

		encryptedContent = encryptedMsg[(asymmCiphertextV1Prefix.length + 512)...]
		return contentKey.decrypt encryptedContent

class PublicKey
	# PRIVATE CONSTRUCTOR
	# Do not call this directly.
	# Use import instead, or use privateKey.getPublicKey()
	constructor: (rawPubEncrKey, rawPubSignKey, check) ->
		unless check is 'iknowwhatimdoing'
			# This is to prevent accidental usage of this constructor outside of this class.
			throw new Error "Use PublicKey.import or PrivateKey.getPublicKey instead"

		unless Buffer.isBuffer rawPubEncrKey
			throw new Error "expected rawPubEncrKey to be a Buffer"

		unless Buffer.isBuffer rawPubSignKey
			throw new Error "expected rawPubSignKey to be a Buffer"

		@_rawPubEncrKey = rawPubEncrKey
		@_rawPubSignKey = rawPubSignKey

	@import: (keyText) ->
		if typeof keyText isnt 'string'
			throw new Error "expected keyText to be a string"

		[prefix, pubEncrKeyB64, pubSignKeyB64] = keyText.split ':'

		unless prefix is pubKeyV1Prefix
			throw new Error "error while importing public key"

		return new PublicKey(
			Base64url.toBuffer(pubEncrKeyB64),
			Base64url.toBuffer(pubSignKeyB64),
			'iknowwhatimdoing'
		)

	export: ->
		return [
			pubKeyV1Prefix,
			Base64url.encode(@_rawPubEncrKey),
			Base64url.encode(@_rawPubSignKey)
		].join ':'

	encrypt: (msg) ->
		if typeof msg is 'string'
			msg = new Buffer(msg, 'utf8')

		unless Buffer.isBuffer msg
			throw new Error "expected message to be a string or Buffer"

		outputBuffers = []

		# Future-proof with a version identifier
		outputBuffers.push asymmCiphertextV1Prefix

		# Generate a new symmetric key and encrypt using RSA
		contentKey = SymmetricEncryptionKey.generate()
		encryptedContentKey = Crypto.publicEncrypt(
			toPemKeyFormat('PUBLIC KEY', @_rawPubEncrKey),
			new Buffer(contentKey.export())
		)
		outputBuffers.push encryptedContentKey

		# Encrypt message with content key
		outputBuffers.push contentKey.encrypt(msg)

		return Buffer.concat outputBuffers

generateSalt = ->
	return Crypto.randomBytes(16).toString('hex')

# A hard-coded key for obfuscating data
# WARNING: do not use this for sensitive data!
# This is just to keep users from getting themselves in trouble by trying to
# change data files by hand.
obfuscationKey = SymmetricEncryptionKey.import("symmkey-v1:6f626675736361746520746865207374756666207769746820746865206b6579")

obfuscate = (buf) ->
	return obfuscationKey.encrypt buf

deobfuscate = (buf) ->
	return obfuscationKey.decrypt buf

module.exports = {
	SymmetricEncryptionKey
	PrivateKey
	PublicKey
	generateSalt
	obfuscate
	deobfuscate
}
