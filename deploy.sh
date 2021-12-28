#!/bin/bash

# must be the project ID for an existing project
PROJECT_ID=yet-another-335918
# the name to use while creating the temp storage bucket
TEMP_BUCKET_NAME=jon_some_temp_bucket
# the name to use while creating the UI bucket
UI_BUCKET_NAME=jon_the_ui_bucket

# ensure these variables are set
if [ -z "$PROJECT_ID" ]
then
      echo "PROJECT_ID is not set"
      exit
fi

if [ -z "$TEMP_BUCKET_NAME" ]
then
      echo "TEMP_BUCKET_NAME is not set"
      exit
fi

if [ -z "$UI_BUCKET_NAME" ]
then
      echo "UI_BUCKET_NAME is not set"
      exit
fi

# init the terraform directory before script execution
if [ ! -d "./terraform/.terraform" ]
then 
    cd ./terraform && terraform init && cd ..
fi

# clean up previous build artifacts
rm -rf build
mkdir build

# zip each cloud function
PYTHON=$(cat <<EOF
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

cd terraform && \
    terraform plan \
        -var "project_id=$PROJECT_ID" \
        -var "temp_storage_bucket_name=$TEMP_BUCKET_NAME" \
        -var "ui_bucket_name=$UI_BUCKET_NAME" && \
    terraform apply \
        -var "project_id=$PROJECT_ID" \
        -var "temp_storage_bucket_name=$TEMP_BUCKET_NAME" \
        -var "ui_bucket_name=$UI_BUCKET_NAME" -auto-approve && \
    cd ..

# build the ui
export NODE_OPTIONS=--openssl-legacy-provider
cd src/ui/ && npm install && npm run build && cd ../..

# clear the bucket of previously built artifacts
gsutil -m rm -r "gs://$UI_BUCKET_NAME/*"

# the easiest way to upload entire directory contents into a bucket (without zip)
gsutil cp -r ./src/ui/build/* "gs://$UI_BUCKET_NAME"