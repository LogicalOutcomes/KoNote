Async = require 'async'
ChildProcess = require 'child_process'
Fs = require 'fs'
Os = require 'os'
Path = require 'path'

{generateId} = require './utils'

# This is a special script written to run on "Windows Scripting Host".
# This allows me to access Windows-specific functionality without having to
# write native code.
# Fun fact: this isn't actually JavaScript, it's Microsoft's proprietary
# implementation of JavaScript called "JScript".
windowsLockScript = '''
	var fso = new ActiveXObject('Scripting.FileSystemObject');
	var stdout = WScript.StdOut;
	var stdin = WScript.StdIn;

	var lockFilePath = WScript.Arguments(0);

	var fd = fso.OpenTextFile(lockFilePath, 8);
	stdout.WriteLine('locked');

	var cmd = stdin.ReadLine();
	if (cmd !== 'unlock') {
		throw new Error("unknown command: " + cmd);
	}

	fd.Close();
	stdout.WriteLine('unlocked');
'''

acquireLock = (lockFilePath, cb) ->
	lockFilePath = Path.resolve lockFilePath

	Async.waterfall [
		(cb) ->
			Fs.exists lockFilePath, (exists) ->
				cb null, exists
		(exists, cb) ->
			if exists
				cb null
				return

			# Create the lock file since it does not exist.
			# Note: this is not very safe against race conditions, so it's best
			# if this is done infrequently.  Reuse lock files as much as
			# possible; avoid recreating them.
			Fs.writeFile lockFilePath, 'lock', cb
		(cb) ->
			switch Os.platform()
				when 'win32' # Windows
					acquireLock_win32 lockFilePath, cb
				when 'darwin' # Mac OS X
					acquireLock_darwin lockFilePath, cb
				when 'linux' # Linux
					acquireLock_linux lockFilePath, cb
				else
					throw new Error("unknown platform: #{JSON.stringify Os.platform()}")
	], cb

acquireLock_win32 = (lockFilePath, cb) ->
	# Generate a random location for a temp file
	lockScriptPath = Path.join(Os.tmpdir(), generateId() + '.js')

	Async.waterfall [
		(cb) ->
			# Write out the locking script to temp
			Fs.writeFile lockScriptPath, windowsLockScript, cb
		(cb) ->
			# Run locking script
			console.log "exec: CScript.exe #{[lockScriptPath, '//Nologo', lockFilePath].join(' ')}"
			proc = ChildProcess.spawn 'CScript.exe', [lockScriptPath, '//Nologo', lockFilePath], {
				cwd: process.cwd()
				env: process.env
				stdio: 'pipe'
			}

			# Handle output
			hasRunCallback = false
			proc.stderr.on 'data', (data) ->
				if hasRunCallback
					return

				# TODO Add check for "Permission denied" -- means lock conflict
				hasRunCallback = true
				console.error "stderr output from Windows file locking script: #{JSON.stringify data.toString()}"
				cb new Error "stderr output from Windows file locking script"
			proc.stdout.on 'data', (data) ->
				if hasRunCallback
					return

				if data.toString().trim() is ''
					return

				hasRunCallback = true

				if data.toString().trim() isnt 'locked'
					console.error "invalid output from Windows file locking script: #{JSON.stringify data.toString()}"
					cb new Error "error in Windows file locking script"
					return

				# We got the lock!
				hasRunCallback = true
				cb null, {
					release: (cb=(->)) ->
						# When the script exits, we're done
						proc.on 'exit', (code, signal) ->
							cb null

						# Tell the locking script to release the lock
						proc.stdin.write 'unlock\r\n'
				}
	], cb

acquireLock_darwin = (lockFilePath, cb) ->
	throw new Error "not yet implemented on Mac"

acquireLock_linux = (lockFilePath, cb) ->
	throw new Error "not yet implemented on Linux"

module.exports = {acquireLock}
