# Google Cloud Reference Implementation


###### A quickstart project using Terraform to configure a typical website and API, consisting of a Load Balancer, 2 Cloud Functions to handle reading and writing, 1 Cloud Storage bucket serving a React website, and a Cloud SQL Postgres instance.


### Setup

1. Install the Google Cloud SDK (glcoud, gsutil, etc.)
    * `gsutil` is needed to upload unzipped files to a bucket
2. Satisfy [these GCP prerequisites](https://learn.hashicorp.com/tutorials/terraform/google-cloud-platform-build?in=terraform/gcp-get-started) 
    * Ensure to add the `Cloud Functions Admin` permission to the service account (in addition to `Editor`)
3. Sym-link key.json to the key file
    * `cd terraform && ln -s <KEY_FILE_PATH> key.json`
4. Manually enable APIs; when enabling through Terraform, there seems to be race conditions which cause the script to fail
    * [Cloud Functions](https://console.developers.google.com/apis/api/cloudfunctions.googleapis.com/overview?project=<PROJECT_ID>)
    * [Cloud Build](https://console.developers.google.com/apis/api/cloudbuild.googleapis.com/overview?project=<PROJECT_ID>)
    * [Compute](https://console.developers.google.com/apis/api/compute.googleapis.com/overview?project=<PROJECT_ID>)
    * [Cloud Resource Manager](https://console.developers.google.com/apis/api/cloudresourcemanager.googleapis.com/overview?project=<PROJECT_ID>)
    * [Cloud SQL](https://console.developers.google.com/apis/api/sqladmin.googleapis.com/overview?project=<PROJECT_ID)
5. Note that it *may* be necessary to manually enable the cloud billing service
6. Set the `PROJECT_ID`, `TEMP_BUCKET_NAME`, and `UI_BUCKET_NAME` variables accordingly in the `deploy.sh` file
7. `cd terraform && terraform init`
8. Run `./deploy.sh`
    * Note that during the deploy process, a prompt will appear in the shell that will require confirmation
9. [Find the IP address of the load balancer](https://console.cloud.google.com/net-services/loadbalancing/loadBalancers/list?project=<PROJECT_ID>)
    * Navigate to the UI: `http://<IP_ADDRESS>/index.html`
10. To teardown all infrastructure, run `cd terraform && terraform destroy`

### Notes

1. After deployment, it may take 3-10 minutes for the changes to propagate to the edge nodes.
2. Set `export TF_LOG=TRACE` to debug terraform issues
3. To connect to the Cloud SQL database instance locally, use the [Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/mysql/quickstart-proxy-test)
