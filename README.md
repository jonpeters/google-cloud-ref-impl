# Google Cloud Reference Implementation

### Setup

1. Satisfy prerequisites listed here: https://learn.hashicorp.com/tutorials/terraform/google-cloud-platform-build?in=terraform/gcp-get-started 
    * Ensure to add the `Cloud Functions Admin` permission to the service account (in addition to `Editor`)
2. Sym-link key.json to the key file
    * `cd terraform && ln -s <KEY_FILE_PATH> key.json`
3. Manually enable APIs; when enabling through Terraform, there seems to be race conditions which cause the script to fail
    * Cloud Functions - https://console.developers.google.com/apis/api/cloudfunctions.googleapis.com/overview?project=<PROJECT_ID>
    * Cloud Build - https://console.developers.google.com/apis/api/cloudbuild.googleapis.com/overview?project=<PROJECT_ID>
    * Compute - https://console.developers.google.com/apis/api/compute.googleapis.com/overview?project=<PROJECT_ID>
    * Cloud Resource Manager - https://console.developers.google.com/apis/api/cloudresourcemanager.googleapis.com/overview?project=<PROJECT_ID>
4. Note that it *may* be necessary to manually enable the cloud billing service
5. Set the `project_id` and `temp_storage_bucket_name` properties accordingly in the `main.tf` file
6. `cd terraform && terraform init`
7. Run `./deploy.sh`
    * Note that during the deploy process, a prompt will appear in the shell that will require confirmation
8. To teardown all infrastructure, run `cd terraform && terraform destroy`

### Notes

1. After deployment, it may take 3-10 minutes for the changes to propagate to the edge nodes.



