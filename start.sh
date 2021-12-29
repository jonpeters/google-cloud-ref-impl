#!/bin/bash

CONTAINER_NAME=dev
PORT=80

docker container prune -f
docker build ./docker -t $CONTAINER_NAME
docker run -d -v ~/.config:/root/.config \
    -v $(pwd)/terraform/terraform.tfstate:/app/terraform.tfstate \
    -v $(pwd):/app/workspace \
    --name $CONTAINER_NAME \
    -p $PORT:80 \
    -e BUILD_UI=$BUILD_UI \
    $CONTAINER_NAME

# wait for the the UI to be fully build (so deploy.sh script execution halts)
if ! [ -z "$BUILD_UI" ]; then
    docker wait $CONTAINER_NAME
fi
