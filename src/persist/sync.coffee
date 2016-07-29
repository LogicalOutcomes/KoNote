# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

exec = require('child_process').exec;

{IOError} = require './utils'

pull = (count, cb) ->
    if count < 3
        exec global.pull, (err, stdout, stderr) =>
            if err
                count++
                setTimeout (->
                    pull count, cb
                ), 500
            else
                cb()
    else
        cb new IOError

push = (count, cb) ->
    if count < 3
        exec global.push, (err, stdout, stderr) =>
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
