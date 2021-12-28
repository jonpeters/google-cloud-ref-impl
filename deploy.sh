#!/bin/bash

PROJECT_ID=$(gcloud config get-value project)

echo "Using project ID $PROJECT_ID"

# init the terraform directory before script execution
if [ ! -d "./terraform/.terraform" ]; then
    cd ./terraform && terraform init && cd ..
fi

# clean up previous build artifacts
rm -rf build
mkdir build

# zip each cloud function
PYTHON=$(
    cat <<EOF
import os
import shutil
for cf_dir in os.scandir("./src/cloud-functions"):
    dir_name = cf_dir.path.split("/")[-1]
    shutil.copytree(cf_dir.path, f"./build/{dir_name}")
    for entry in os.listdir("./src/shared"):
        if entry == "__pycache__": 
            continue
        entry_path = f"./src/build/{dir_name}/{entry}"
        if os.path.exists(entry_path):
            os.remove(entry_path)
        shutil.copyfile(f"./src/shared/{entry}",  f"./build/{dir_name}/{entry}")
    os.system(f"zip -j ./build/{dir_name}.zip ./build/{dir_name}/*")
EOF
)

python3 -c "$PYTHON"

cd terraform &&
    terraform plan -var "project_id=$PROJECT_ID" &&
    terraform apply -var "project_id=$PROJECT_ID" -auto-approve && cd ..

PYTHON=$(
    cat <<EOF
from jsonpath_rw_ext import parse
import json
tf_state = json.load(open("./terraform/terraform.tfstate"))
expression = parse("$.resources[?name==\"ui_backend_bucket\"].instances[0].attributes.bucket_name")
bucket_name = expression.find(tf_state)[0].value
print(bucket_name)
EOF
)

UI_BUCKET_NAME=$(python3 -c "$PYTHON")

echo $UI_BUCKET_NAME

# build the ui
export NODE_OPTIONS=--openssl-legacy-provider
cd src/ui/ && npm install && npm run build && cd ../..

# clear the bucket of previously built artifacts
gsutil -m rm -r "gs://$UI_BUCKET_NAME/*"

# the easiest way to upload entire directory contents into a bucket (without zip)
gsutil cp -r ./src/ui/build/* "gs://$UI_BUCKET_NAME"
