#!/bin/bash

CONTAINER_NAME=dev
PORT=80

# TODO start cloud_sql_proxy outside of docker to support dev clients

# read cloud function local configs to find debug ports
PYTHON=$(
    cat <<EOF
import os
import json
ports = []
path = "./src/cloud-functions"
for cf_dir in os.scandir(path):
    config_path = f"{cf_dir.path}/config.json"
    if os.path.exists(config_path):
        with open(config_path) as file:
            config_dict = json.loads(file.read())
            ports.append(config_dict.get("debug-port"))
port_args = " ".join([f"-p {port}:{port}" for port in ports])
print(port_args)
EOF
)
DEBUG_PORT_ARGS=$(python3 -c "$PYTHON")

docker container prune -f
docker build ./docker -t $CONTAINER_NAME
docker run -d -v ~/.config:/root/.config \
    -v $(pwd)/terraform/terraform.tfstate:/app/terraform.tfstate \
    -v $(pwd):/app/workspace \
    --name $CONTAINER_NAME \
    -p $PORT:80 \
    $DEBUG_PORT_ARGS \
    -e BUILD_UI=$BUILD_UI \
    $CONTAINER_NAME

# wait for the the UI to be fully build (so deploy.sh script execution halts)
if ! [ -z "$BUILD_UI" ]; then
    docker wait $CONTAINER_NAME
fi
