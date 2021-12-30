# read the project id from gcloud
PROJECT_ID=$(gcloud config get-value project)
echo "Using project ID $PROJECT_ID"

# set this to allow tooling to find credentials
export GOOGLE_APPLICATION_CREDENTIALS=$PWD/$PROJECT_ID-key.json

cd terraform
terraform destroy -var "project_id=$PROJECT_ID" 
cd ..