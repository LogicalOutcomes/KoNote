#!/usr/bin/env coffee

# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Use this script from a command line.
# Pipe encrypted data into stdin, and it will output decrypted data on stdout.
# Alternatively, specify a file path, and it will read the encrypted data, and
# output decrypted data on stdout.
#
# Example:
#   scripts/decrypt.coffee data user pw data/clientFiles/some-encrypted-file

Fs = require 'fs'

{SymmetricEncryptionKey} = require '../src/persist/crypto'
Users = require '../src/persist/users'

if process.argv.length not in [5, 6]
	console.error "Usage: <command> <data_directory> <user_name> <password> [<encrypted_file>]"
	console.error "If encrypted_file is omitted, data will be read from stdin."
	return

dataDir = process.argv[2]
userName = process.argv[3]
password = process.argv[4]
encryptedFile = process.argv[5]

backend = {
	type: 'file-system'
	dataDirectory: dataDir
}

Users.Account.read backend, userName, (err, account) =>
	if err
		console.error err.stack
		return

	account.decryptWithPassword password, (err, decryptedAccount) =>
		if err
			console.error err.stack
			return

		globalEncryptionKey = SymmetricEncryptionKey.import decryptedAccount.privateInfo.globalEncryptionKey

		readEncryptedFile (err, encryptedInput) =>
			if err
				console.error err.stack
				return

			process.stdout.write globalEncryptionKey.decrypt encryptedInput

readEncryptedFile = (cb) =>
	if encryptedFile
		cb null, Fs.readFileSync encryptedFile
		return

	inputBufs = []

	process.stdin.on 'readable', =>
		chunkBuf = process.stdin.read()

		if chunkBuf isnt null
			inputBufs.push chunkBuf

	process.stdin.on 'end', =>
		encryptedInput = Buffer.concat inputBufs

		cb null, encryptedInput
