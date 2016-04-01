# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# This module defines all cryptographic operations (encryption, digital
# signatures, etc) used in this project.
#
# Full API documentation is available on the wiki.
#
# WARNING: This code is delicate.  I strongly recommend avoiding changing this
# code if possible.  Ask Tim McLean <tim@timmclean.net> to review any and all
# changes, even refactors.

Assert = require 'assert'
Async = require 'async'
Base64url = require 'base64url'
BufferEq = require 'buffer-equal-constant-time'
Crypto = require 'crypto'

symmKeyV1Prefix = 'symmkey-v1'
symmCiphertextV1Prefix = new Buffer([1])

rsaKeyLength = 3072
privKeyV1Prefix = 'privkey-v1'
pubKeyV1Prefix = 'pubkey-v1'
asymmCiphertextV1Prefix = new Buffer([1])

WebCryptoApi = ->
	# Hi there, programmer from the future.
	# Yup, it has a double underscore, and yes, I used it.
	# I wish there was a better way.
	#
	# If this broke, all you need to do is find a way to get a valid JavaScript
	# `window` object from a browsing context,
	# and get a reference to the Web Crypto API.
	#
	# Oh, by the way, avoid global.window (see issue 473).

	Assert global.__nwWindowsStore, 'this version of NW.js does not have __nwWindowsStore'

	# Grab the first NW.js Window that we can find
	nwWin = global.__nwWindowsStore[Object.keys(global.__nwWindowsStore)[0]]

	# Pull a reference out of the window
	return nwWin.window.crypto.subtle

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

class WeakSymmetricEncryptionKey
	# Weakened in order to produce shorter ciphertexts.
	# Whenever possible, use SymmetricEncryptionKey instead.
	#
	# The encryption scheme is mostly as described here:
	# https://crypto.stackexchange.com/questions/30905/using-hmac-as-a-nonce-with-aes-ctr-encrypt-and-mac
	#
	# In this implementation:
	# - A single key is used for both AES-CTR and HMAC
	# - The HMAC output is truncated to a configurable value `tagLength`
	#
	# tagLength values can range 0-32 bytes.  A tagLength of 16 or more is
	# essentially "full security", while a tagLength of 0 is approximately no
	# security.
	#
	# tagLength impacts security in two ways.  First, the length of the tag
	# determines the probability that an attacker is able to forge (i.e. tamper
	# with) a message.  This probability is 2^(-8*tagLength), which means that,
	# with tagLength=1, the attacker should succeed after about 256 attempts.
	#
	# Second, tagLength determines the probability that the same nonce is used
	# to encrypt more than one message.  When a nonce is reused, an attacker
	# can usually crack the encryption on those two encrypted messages.  The
	# first nonce reuse is expected to occur after about 2^(4*tagLength)
	# unique messages are encrypted.  Thus, it is important to choose tagLength
	# based on how many messages are expected to be encrypted.

	constructor: (symmKey, tagLength) ->
		unless symmKey instanceof SymmetricEncryptionKey
			throw new Error "expected symmKey to be a SymmetricEncryptionKey"

		unless typeof tagLength is 'number'
			throw new Error "expected tagLength to be a number"

		if tagLength > 32
			throw new Error "tagLength must be <= 32"

		if tagLength < 0
			throw new Error "tagLength must be >= 0"

		# Derive a separate key just for this class
		# This avoids the same key being used for multiple algorithms
		# New key is HMAC-SHA256(symmKey, "new key for weak encryption")
		kdf = Crypto.createHmac('sha256', symmKey._rawKeyMaterial)
		kdf.update new Buffer('new key for weak encryption', 'utf8')
		@_rawKeyMaterial = kdf.digest()

		@_tagLength = tagLength

	encrypt: (msg) ->
		if typeof msg is 'string'
			msg = new Buffer(msg, 'utf8')

		unless Buffer.isBuffer msg
			throw new Error "expected msg to be a string or Buffer"

		# Compute HMAC-SHA256(key, msg)
		hmac = Crypto.createHmac('sha256', @_rawKeyMaterial)
		hmac.update msg
		fullHmacTag = hmac.digest()

		# Truncate HMAC tag to specified security level
		tag = fullHmacTag.slice(0, @_tagLength)

		# Encrypt plaintext with AES256-CTR, using tag as nonce
		outputBuffers = []
		paddedTag = padBufferRight(tag.slice(0, 16), 0, 16)
		cipher = Crypto.createCipheriv('aes-256-ctr', @_rawKeyMaterial, paddedTag)
		outputBuffers.push cipher.update msg
		outputBuffers.push cipher.final()

		outputBuffers.push tag

		# Return ciphertext + tag
		return Buffer.concat outputBuffers

	decrypt: (encryptedMsg) ->
		unless Buffer.isBuffer encryptedMsg
			throw new Error "expected encryptedMsg to be a Buffer"

		if encryptedMsg.length < @_tagLength
			throw new Error "encryptedMsg is too short"

		# Separate out ciphertext and auth tag
		ciphertext = encryptedMsg.slice(0, -@_tagLength)
		tag = encryptedMsg.slice(-@_tagLength)

		# Decrypt ciphertext
		plaintextBuffers = []
		paddedTag = padBufferRight(tag.slice(0, 16), 0, 16)
		decipher = Crypto.createDecipheriv('aes-256-ctr', @_rawKeyMaterial, paddedTag)
		plaintextBuffers.push decipher.update ciphertext
		plaintextBuffers.push decipher.final()
		plaintext = Buffer.concat plaintextBuffers

		# Check tag
		hmac = Crypto.createHmac('sha256', @_rawKeyMaterial)
		hmac.update plaintext
		expectedTag = hmac.digest().slice(0, @_tagLength)

		unless BufferEq(tag, expectedTag)
			throw new Error "tampering detected"

		return plaintext

class PrivateKey
	# Implementation notes:
	# - Signing not yet implemented, except for key generation
	# - Encryption is hybrid encryption using RSA and AES-GCM
	# - RSA-OAEP with a 3072-bit modulus and MGF1+SHA256 (e=65537)
	# - AES-GCM uses a new random key for each message
	# - See SymmetricEncryptionKey for AES-GCM implementation notes
	# - Underlying primitives are from Web Crypto until we upgrade NW.js

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
		privEncrKey = null
		pubEncrKey = null
		privSignKey = null
		pubSignKey = null

		Async.series [
			(cb) ->
				console.info "Step 1"
				usePromise WebCryptoApi().generateKey(
					{
						name: 'RSA-OAEP'
						modulusLength: rsaKeyLength
						publicExponent: new Uint8Array([1, 0, 1]) # 65537
						hash: {name: 'SHA-256'}
					},
					true, # extractable
					['encrypt', 'decrypt']
				), (err, keyPair) ->
					if err
						console.info "ERROR with step 1"
						cb err
						return

					privEncrKey = keyPair.privateKey
					pubEncrKey = keyPair.publicKey
					cb()
			(cb) ->
				console.info "Step 2"
				usePromise WebCryptoApi().generateKey(
					{
						name: 'RSASSA-PKCS1-v1_5'
						modulusLength: rsaKeyLength
						publicExponent: new Uint8Array([1, 0, 1]) # 65537
						hash: {name: 'SHA-256'}
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
				console.info "Step 3"
				Async.map [
					[privEncrKey, 'pkcs8']
					[pubEncrKey, 'spki']
					[privSignKey, 'pkcs8']
					[pubSignKey, 'spki']
				], ([key, format], cb) ->
					usePromise WebCryptoApi().exportKey(format, key), (err, exportedKeyBuf) ->
						if err
							cb err
							return

						cb null, fromUint8Array exportedKeyBuf
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

			console.info "Step DONE"

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

	decrypt: (encryptedMsg, cb) ->
		unless Buffer.isBuffer encryptedMsg
			throw new Error "expected encryptedMsg to be a Buffer"

		prefix = encryptedMsg[...asymmCiphertextV1Prefix.length]
		unless BufferEq(prefix, asymmCiphertextV1Prefix)
			throw new Error "unknown encryption version"

		# next <key length> bytes
		encryptedContentKey =
			encryptedMsg[asymmCiphertextV1Prefix.length...(asymmCiphertextV1Prefix.length + rsaKeyLength/8)]

		# BEGIN NW.js v0.11 code
		usePromise WebCryptoApi().importKey(
			'pkcs8', toUint8Array(@_rawPrivEncrKey),
			{
				name: 'RSA-OAEP'
				hash: {name: 'SHA-256'}
			},
			true, ['decrypt']
		), (err, webCryptoKey) =>
			if err
				cb err
				return

			usePromise WebCryptoApi().decrypt(
				{name: 'RSA-OAEP'}, webCryptoKey, toUint8Array(encryptedContentKey)
			), (err, contentKeyText) =>
				if err
					cb err
					return

				contentKey = SymmetricEncryptionKey.import(
					fromUint8Array(contentKeyText).toString()
				)

				encryptedContent = encryptedMsg[(asymmCiphertextV1Prefix.length + rsaKeyLength/8)...]
				cb null, contentKey.decrypt encryptedContent
		# END NW.js v0.11 code

		# BEGIN NW.js v0.12+ code
#		contentKeyText = Crypto.privateDecrypt(
#			toPemKeyFormat('PRIVATE KEY', @_rawPrivEncrKey),
#			encryptedContentKey
#		)
#		contentKey = SymmetricEncryptionKey.import(contentKeyText.toString())
#
#		encryptedContent = encryptedMsg[(asymmCiphertextV1Prefix.length + rsaKeyLength/8)...]
#		return contentKey.decrypt encryptedContent
		# END NW.js v0.12+ code

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

	encrypt: (msg, cb) ->
		if typeof msg is 'string'
			msg = new Buffer(msg, 'utf8')

		unless Buffer.isBuffer msg
			throw new Error "expected message to be a string or Buffer"

		outputBuffers = []

		# Future-proof with a version identifier
		outputBuffers.push asymmCiphertextV1Prefix

		# Generate a new symmetric key and encrypt using RSA
		contentKey = SymmetricEncryptionKey.generate()
		# BEGIN NW.js v0.11 code
		usePromise WebCryptoApi().importKey(
			'spki', toUint8Array(@_rawPubEncrKey),
			{
				name: 'RSA-OAEP'
				hash: {name: 'SHA-256'}
			},
			true, ['encrypt']
		), (err, webCryptoKey) =>
			if err
				cb err
				return

			usePromise WebCryptoApi().encrypt(
				{name: 'RSA-OAEP'}, webCryptoKey, toUint8Array(new Buffer(contentKey.export()))
			), (err, encryptedContentKey) =>
				if err
					cb err
					return

				outputBuffers.push fromUint8Array(encryptedContentKey)

				# Encrypt message with content key
				outputBuffers.push contentKey.encrypt(msg)

				cb null, Buffer.concat outputBuffers
		# END NW.js v0.11 code

		# BEGIN NW.js v0.12+ code
#		encryptedContentKey = Crypto.publicEncrypt(
#			toPemKeyFormat('PUBLIC KEY', @_rawPubEncrKey),
#			new Buffer(contentKey.export())
#		)
#		outputBuffers.push encryptedContentKey
#
#		# Encrypt message with content key
#		outputBuffers.push contentKey.encrypt(msg)
#
#		return Buffer.concat outputBuffers
		# END NW.js v0.12+ code

generateSalt = ->
	# 128-bit salt
	# probably overkill
	return Crypto.randomBytes(16).toString('hex')

generatePassword = ->
	# 96 bits of entropy
	# Uses uppercase and lowercase alphanumeric, underscore (_) and hyphen (-)
	# Warning: this method is not constant-time
	return Base64url.encode Crypto.randomBytes(12)

# A hard-coded key for obfuscating data
# WARNING: do not use this for sensitive data!
# This is just to keep users from getting themselves in trouble by trying to
# change data files by hand.
obfuscationKey = SymmetricEncryptionKey.import("symmkey-v1:6f626675736361746520746865207374756666207769746820746865206b6579")

obfuscate = (buf) ->
	return obfuscationKey.encrypt buf

deobfuscate = (buf) ->
	return obfuscationKey.decrypt buf

# Pad the end of the buffer with padByte up to length
padBufferRight = (buf, padByte, length) ->
	if buf.length > length
		throw new Error "input buffer already exceeds desired length"

	result = new Buffer(length)
	result.fill padByte

	buf.copy result

	return result

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

fromUint8Array = (uint8s) ->
	uint8s = new Uint8Array uint8s
	result = new Buffer(uint8s.length)

	for i in [0...result.length]
		result[i] = uint8s[i]

	return result

toUint8Array = (buf) ->
	unless Buffer.isBuffer buf
		throw new Error "expected Buffer"

	result = new Uint8Array(buf.length)

	for i in [0...result.length]
		result[i] = buf[i]

	return result

module.exports = {
	SymmetricEncryptionKey
	WeakSymmetricEncryptionKey
	PrivateKey
	PublicKey
	generateSalt
	generatePassword
	obfuscate
	deobfuscate
}
