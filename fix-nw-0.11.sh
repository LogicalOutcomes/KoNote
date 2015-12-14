#!/bin/bash

# Before v0.12, NW.js needs this patch on 64-bit Linux

set -o nounset
set -o errexit

npm install
cat node_modules/nodewebkit/nodewebkit/nw | sed 's/libudev.so.0/libudev.so.1/' > fixed-nw-temp
mv fixed-nw-temp node_modules/nodewebkit/nodewebkit/nw
chmod u+x node_modules/nodewebkit/nodewebkit/nw
