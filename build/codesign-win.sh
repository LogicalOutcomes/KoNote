#!/usr/bin/env bash

# script to codesign windows exe on osx
# requires mono tools (www.mono-project.com) and valid authenticode certificate in SPC/PVK format
# parameters: $2=file to sign, $1=pvk password

spcFile="/Users/tyler/dev/certs/konote-codesign-win.spc"
pvkFile="/Users/tyler/dev/certs/konote-codesign-win.pvk"

echo ">>> start windows codesign"

echo $1 | signcode \
-spc $spcFile \
-v $pvkFile \
-a sha1 -$ commercial \
-n KoNote \
-i http://konote.ca/ \
-t http://timestamp.verisign.com/scripts/timstamp.dll \
-tr 5 \
$2

echo ">>> verifying signature"

chktrust $2

echo ">>> done!"
