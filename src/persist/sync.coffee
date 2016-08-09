# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

exec = require('child_process').exec;
Fs = require 'fs'
{IOError} = require './utils'
Config = require '../config'

if process.platform is 'win32'
    pullCmd = "set PATH=#{process.cwd()}\\cwrsync;%PATH%\nrsync -azP --partial --delete --exclude 'data/_tmp' -e 'ssh -o StrictHostKeyChecking=no -i id_rsa' #{Config.cloudUser}@cloud.konote.ca:data ."
    Fs.writeFileSync 'pull.cmd', pullCmd
    pullCmd = 'pull.cmd'

    pushCmd = "set PATH=#{process.cwd()}\\cwrsync;%PATH%\nrsync -azP --partial --delete --exclude 'data/_tmp' -e 'ssh -o StrictHostKeyChecking=no -i id_rsa' data/ #{Config.cloudUser}@cloud.konote.ca:data"
    Fs.writeFileSync 'push.cmd', pushCmd
    pushCmd = 'push.cmd'

    pullLocksCmd = "set PATH=#{process.cwd()}\\cwrsync;%PATH%\nrsync -azP --partial --delete -e 'ssh -o StrictHostKeyChecking=no -i id_rsa' #{Config.cloudUser}@cloud.konote.ca:data/_locks data/"
    Fs.writeFileSync 'pullLocks.cmd', pullLocksCmd
    pullLocksCmd = 'pullLocks.cmd'

    pushLocksCmd = "set PATH=#{process.cwd()}\\cwrsync;%PATH%\nrsync -azP --partial --delete -e 'ssh -o StrictHostKeyChecking=no -i id_rsa' data/_locks/ #{Config.cloudUser}@cloud.konote.ca:data/_locks"
    Fs.writeFileSync 'pushLocks.cmd', pushLocksCmd
    pushLocksCmd = 'pushLocks.cmd'

else
    pullCmd = "rsync -azP --partial --delete --exclude 'data/_tmp' -e 'ssh -o StrictHostKeyChecking=no -i id_rsa' #{Config.cloudUser}@cloud.konote.ca:data ."
    pushCmd = "rsync -azP --partial --delete --exclude 'data/_tmp' -e 'ssh -o StrictHostKeyChecking=no -i id_rsa' data/ #{Config.cloudUser}@cloud.konote.ca:data"
    pushLocksCmd = "rsync -azP --partial --delete -e 'ssh -o StrictHostKeyChecking=no -i id_rsa' data/_locks/ #{Config.cloudUser}@cloud.konote.ca:data/_locks"
    pullLocksCmd = "rsync -azP --partial --delete -e 'ssh -o StrictHostKeyChecking=no -i id_rsa' #{Config.cloudUser}@cloud.konote.ca:data/_locks data/"


pull = (count, cb) ->
    if global.syncing is false
        console.log "pulling data..."
        global.syncing = true
        if count < 2
            exec pullCmd, (err, stdout, stderr) =>
                if err
                    console.error err
                    count++
                    global.syncing = false
                    pull count, cb
                else
                    if global.ActiveSession
                        global.ActiveSession.persist.eventBus.trigger 'clientSelectionPage:pulled'
                    setTimeout (->
                        global.syncing = false
                    ), 1000
                    cb()
        else
            setTimeout (->
                global.syncing = false
            ), 1000
            console.log "pull failure"
            cb new IOError "Pull failed"
    else
        cb()

push = (count, cb) ->
    console.log "pushing data..."
    global.syncing = true
    if count < 2
        exec pushCmd, (err, stdout, stderr) =>
            if err
                count++
                global.syncing = false
                push count, cb
            else
                global.syncing = false
                cb()
    else
        global.syncing = false
        cb new IOError "Push failed"


module.exports = {
    pull
    push
}
