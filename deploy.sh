#!/bin/bash

# must be the project ID for an existing project
PROJECT_ID=before-commit
# the name to use while creating the temp storage bucket
TEMP_BUCKET_NAME=temp-bucket-please-delete-me-121212
# the name to use while creating the UI bucket
UI_BUCKET_NAME=the-ui-bucket-75757575

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
rm -f ./src/cloud-functions/writer/writer.zip
rm -f ./src/cloud-functions/reader/reader.zip

# need to manually (i.e. via bash, not terraform) create zip files because of lacking ARM64 support
cd src/cloud-functions/writer
zip writer.zip *
cd ../reader
zip reader.zip *
cd ../../..

cd terraform && \
    terraform plan \
        -var "project_id=$PROJECT_ID" \
        -var "temp_storage_bucket_name=$TEMP_BUCKET_NAME" \
        -var "ui_bucket_name=$UI_BUCKET_NAME" && \
    terraform apply \
        -var "project_id=$PROJECT_ID" \
        -var "temp_storage_bucket_name=$TEMP_BUCKET_NAME" \
        -var "ui_bucket_name=$UI_BUCKET_NAME" && \
    cd ..

# build the ui
cd src/ui/ && npm run build && cd ../..

# clear the bucket of previously built artifacts
gsutil -m rm -r "gs://$UI_BUCKET_NAME/*"

# the easiest way to upload entire directory contents into a bucket (without zip)
gsutil cp -r ./src/ui/build/* "gs://$UI_BUCKET_NAME"