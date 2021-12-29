#!/bin/bash

# start the full local stack
if [ -z "$BUILD_UI" ]; then
    python3 run.py
    nginx -g 'daemon off;'
# only build the ui and then allow container to exit
else
    rm -rf ./workspace/build/ui
    mkdir -p ./workspace/build/ui
    cp -R ./workspace/src/ui ./workspace/build
    npm --prefix ./workspace/build/ui install && npm --prefix ./workspace/build/ui run build
fi