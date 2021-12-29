#!/bin/bash

# read command line args
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    -i | --project-id)
        PROJECT_ID="$2"
        shift # past argument
        shift # past value
        ;;
    -d | --display-name)
        PROJECT_DISPLAY_NAME="$2"
        shift # past argument
        shift # past value
        ;;
    *)        # unknown option
        shift # past argument
        ;;
    esac
done

if [ -z "$PROJECT_ID" ]; then
    echo "--project-id must be set"
    exit
fi

if [ -z "$PROJECT_DISPLAY_NAME" ]; then
    echo "--display-name must be set"
    exit
fi

# install gcloud if needed
GC_CMD=$(gcloud 2>&1)
if [[ "$GC_CMD" == *"command not found"* ]]; then
    echo "Installing gcloud ..."
    curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-367.0.0-linux-x86_64.tar.gz
    mv google-cloud-sdk-367.0.0-linux-x86_64.tar.gz ~/.
    tar -xzf ~/google-cloud-sdk-367.0.0-linux-x86_64.tar.gz -C ~/.
    CLOUDSDK_CORE_DISABLE_PROMPTS=1 ~/google-cloud-sdk/install.sh \
        --usage-reporting false --path-update true --additional-components alpha beta pubsub-emulator
    echo
    echo "Please close the shell, and execute this script in a new shell"
    echo
    exit
fi

ACCOUNT_INFO=$(gcloud config get-value account)
if [ -z "$ACCOUNT_INFO" ]; then
    gcloud auth login
fi

# find what project is set in gcloud
GCLOUD_PROJECT_ID=$(gcloud config get-value project)

# create the project
if [ "$PROJECT_ID" != "$GCLOUD_PROJECT_ID" ]; then
    gcloud projects create $PROJECT_ID --name="$PROJECT_DISPLAY_NAME"
    # set the new project id into the gcloud context, as downstream components use this
    gcloud config set project "$PROJECT_ID"
fi

# link the billing account
BILLING_ID=($(gcloud alpha billing accounts list --format="value(ACCOUNT_ID)"))
echo "Linking billing ID $BILLING_ID to project $PROJECT_ID ..."
gcloud alpha billing projects link $PROJECT_ID --billing-account $BILLING_ID

# enable apis
APIS=(cloudfunctions.googleapis.com cloudbuild.googleapis.com compute.googleapis.com cloudresourcemanager.googleapis.com sqladmin.googleapis.com)
for API in "${APIS[@]}"; do
    echo "Enabling $API ..."
    RESULT=$(gcloud services enable $API)
    if [ -z "$RESULT" ]; then
        RESULT="$API is already enabled"
    fi
    echo $RESULT
done

# create a service account
SERVICE_ACCT_NAME="$PROJECT_ID-sa"
gcloud iam service-accounts create $SERVICE_ACCT_NAME --display-name="$PROJECT_ID Service Account"

# get full email id of new service account
FULL_ID=$(gcloud iam service-accounts list --filter="email ~ ^$SERVICE_ACCT_NAME" --format='value(email)')

# assign roles to service account necessary for this project
ROLES=(roles/editor roles/cloudsql.admin roles/cloudfunctions.admin)
for ROLE in "${ROLES[@]}"; do
    gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$FULL_ID --role=$ROLE
done

# download the key to the project dir
gcloud iam service-accounts keys create $PROJECT_ID-key.json --iam-account $FULL_ID
