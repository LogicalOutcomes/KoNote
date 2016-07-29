# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

exec = require('child_process').exec;

{IOError} = require './utils'

if process.platform is 'win32'
    pullCmd = "set PATH=%PATH%;#{process.cwd()}\\cwrsync\nrsync -azP --partial --delete -e 'ssh -o StrictHostKeyChecking=no -i authkey' konode@cloud.konote.ca:data ."
    Fs.writeFileSync 'pull.cmd', pullCmd
    pullCmd = 'pull.cmd'

    pushCmd = "set PATH=%PATH%;#{process.cwd()}\\cwrsync\nrsync -azP --partial --delete --exclude 'data/_tmp' -e 'ssh -o StrictHostKeyChecking=no -i authkey' data/ konode@cloud.konote.ca:data"
    Fs.writeFileSync 'push.cmd', pushCmd
    pushCmd = 'push.cmd'

    pullLocksCmd = "set PATH=%PATH%;#{process.cwd()}\\cwrsync\nrsync -azP --partial --delete -e 'ssh -o StrictHostKeyChecking=no -i authkey' konode@cloud.konote.ca:data/_locks data/"
    Fs.writeFileSync 'pullLocks.cmd', pullLocksCmd
    pullLocksCmd = 'pullLocks.cmd'

    pushLocksCmd = "set PATH=%PATH%;#{process.cwd()}\\cwrsync\nrsync -azP --partial --delete -e 'ssh -o StrictHostKeyChecking=no -i authkey' data/_locks/ konode@cloud.konote.ca:data/_locks"
    Fs.writeFileSync 'pushLocks.cmd', pushLocksCmd
    pushLocksCmd = 'pushLocks.cmd'

else
    pullCmd = "rsync -azP --partial --delete -e 'ssh -o StrictHostKeyChecking=no -i authkey' konode@cloud.konote.ca:data ."
    pushCmd = "rsync -azP --partial --delete --exclude 'data/_tmp' -e 'ssh -o StrictHostKeyChecking=no -i authkey' data/ konode@cloud.konote.ca:data"
    pushLocksCmd = "rsync -azP --partial --delete -e 'ssh -o StrictHostKeyChecking=no -i authkey' data/_locks/ konode@cloud.konote.ca:data/_locks"
    pullLocksCmd = "rsync -azP --partial --delete -e 'ssh -o StrictHostKeyChecking=no -i authkey' konode@cloud.konote.ca:data/_locks data/"


pull = (count, cb) ->
    if count < 3
        exec pullCmd, (err, stdout, stderr) =>
            if err
                count++
                setTimeout (->
                    pull count, cb
                ), 500
            else
                if global.ActiveSession
                    global.ActiveSession.persist.eventBus.trigger 'clientSelectionPage:pulled'
                cb()
    else
        cb new IOError "Network unavailable"

push = (count, cb) ->
    if count < 3
        exec pushCmd, (err, stdout, stderr) =>
            if err
                count++
                setTimeout (->
                    push count, cb
                ), 500
            else
                cb()
    else
        cb new IOError


module.exports = {
    pull
    push
}
