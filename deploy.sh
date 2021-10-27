#!/bin/bash

# TODO read project ID from command line

# init the terraform directory before script execution
if [ ! -d "./terraform/.terraform" ]
then 
    cd ./terraform && terraform init && cd ..
fi

# clean up old zip files
rm -f ./src/cloud-functions/writer/writer.zip
rm -f ./src/cloud-functions/reader/reader.zip

# need to manually (i.e. via bash, not terraform) create zip files because of lacking ARM64 support
cd src/cloud-functions/writer
zip writer.zip *
cd ../reader
zip reader.zip *
cd ../../..

cd terraform && terraform plan && terraform apply
cd ..
