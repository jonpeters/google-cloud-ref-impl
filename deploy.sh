#!/bin/bash

# install terraform if needed
TF_CMD=$(terraform 2>&1)
if [[ "$TF_CMD" == *"command not found"* ]]; then
    sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
    sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    sudo apt-get update && sudo apt-get install terraform
fi

# check for venv directory
if ! [ -d "venv" ]; then
    echo
    echo "No virtual environment directory exists!"
    echo
    echo "Copy and execute the following command (and then re-run deploy.sh):"
    echo
    echo "   python3 -m venv ./venv/ && source ./venv/bin/activate && python3 -m pip install -r requirements.txt"
    echo
    exit
fi

# this script must run in a virtual environment
if [ -z "$VIRTUAL_ENV" ]; then
    echo "This script should be executed within an active virtual environment: run 'source venv/bin/activate' and then try again"
    exit
fi

# read the project id from gcloud
PROJECT_ID=$(gcloud config get-value project)
echo "Using project ID $PROJECT_ID"

# set this to allow tooling to find credentials
export GOOGLE_APPLICATION_CREDENTIALS=$PWD/$PROJECT_ID-key.json

# check for existing terraform files; removing them would make it impossible for terraform to control the referenced project
PYTHON=$(
    cat <<EOF
from jsonpath_rw_ext import parse
import json
tf_state = json.load(open("./terraform/terraform.tfstate"))
expression = parse("$.outputs.output_project_id.value")
project_id = expression.find(tf_state)[0].value
print(project_id)
EOF
)
if [ -f "./terraform/terraform.tfstate" ]; then
    TF_PROJECT_ID=$(python3 -c "$PYTHON")
    if [ "$PROJECT_ID" != "$TF_PROJECT_ID" ]; then
        echo "Found existing terraform state files for a different project '$TF_PROJECT_ID'; exiting."
        exit
    fi
fi

# init the terraform directory before script execution
cd terraform && terraform init && cd ..

# clean up previous build artifacts
sudo rm -rf build && mkdir build

# zip each cloud function (terraform can do this but not on an ARM64 chip)
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

# run terraform plan and apply to deploy the artifacts to the cloud
terraform -chdir=./terraform/ plan -var "project_id=$PROJECT_ID" &&
    terraform -chdir=./terraform/ apply -var "project_id=$PROJECT_ID" -auto-approve

# read the tfstate file to find the name of the created ui bucket
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
echo "Using UI bucket $UI_BUCKET_NAME"

# build the ui inside the container
BUILD_UI=1 ./start.sh

# clear the bucket of previously built artifacts
gsutil -m rm -r "gs://$UI_BUCKET_NAME/*"

# the easiest way to upload entire directory contents into a bucket (without zip)
gsutil cp -r ./build/ui/build/* "gs://$UI_BUCKET_NAME"
