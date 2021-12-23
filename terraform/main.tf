variable "temp_storage_bucket_name" {
  type = string
}

variable "ui_bucket_name" {
  type = string
}

variable "project_id" {
  type = string
}

# TODO move these to secret manager
locals {
  database_user     = "me"
  database_password = "changeme"
  database_name     = "my-database"
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.89.0"
    }
  }
}

provider "google" {
  credentials = file("key.json")

  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-a"
}

# bucket to store deployment artifacts; e.g. cloud function zip packages
resource "google_storage_bucket" "bucket" {
  name = var.temp_storage_bucket_name
}

# bucket to store the user interface files
resource "google_storage_bucket" "ui_bucket" {
  name          = var.ui_bucket_name
  force_destroy = true
}

# backend bucket config for load balancer
resource "google_compute_backend_bucket" "ui_backend_bucket" {
  name        = "ui-backend-bucket"
  description = "The bucket holding the UI resources"
  bucket_name = google_storage_bucket.ui_bucket.name
  enable_cdn  = true
}

# make the bucket public for viewing
# TODO remove this, and use API Gateway in front of cloud function
resource "google_storage_bucket_iam_member" "member" {
  bucket = google_storage_bucket.ui_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# zip file for pubsub function
resource "google_storage_bucket_object" "pubsub_archive" {
  name   = "pubsub.zip"
  bucket = google_storage_bucket.bucket.name
  source = "../src/cloud-functions/pubsub/pubsub.zip"
}

# zip file for http-handler function
resource "google_storage_bucket_object" "http_handler_archive" {
  name   = "http-handler.zip"
  bucket = google_storage_bucket.bucket.name
  source = "../src/cloud-functions/http-handler/http-handler.zip"
}

# create the pubsub cloud function
resource "google_cloudfunctions_function" "pubsub_function" {
  name        = "pubsub-function"
  description = "pubsub Function"
  runtime     = "python39"

  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.pubsub_archive.name
  entry_point           = "pubsub"

   event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   =  google_pubsub_topic.example_topic.name
    failure_policy {
      retry = true
    }
  }

  environment_variables = {
    CONNECTION_NAME = google_sql_database_instance.db.connection_name
    USER            = local.database_user
    PASSWORD        = local.database_password
    DATABASE        = local.database_name
  }
}

# make pubsub function public
# TODO remove this, and use API Gateway in front of cloud function
resource "google_cloudfunctions_function_iam_member" "pubsub_invoker" {
  project        = google_cloudfunctions_function.pubsub_function.project
  region         = google_cloudfunctions_function.pubsub_function.region
  cloud_function = google_cloudfunctions_function.pubsub_function.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# create the http-handler cloud function
resource "google_cloudfunctions_function" "http_handler_function" {
  name        = "http-handler-function"
  description = "HTTP Handler Function"
  runtime     = "python39"

  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.http_handler_archive.name
  trigger_http          = true
  entry_point           = "http_handler"

  environment_variables = {
    CONNECTION_NAME = google_sql_database_instance.db.connection_name
    USER            = local.database_user
    PASSWORD        = local.database_password
    DATABASE        = local.database_name
    TOPIC_ID        = google_pubsub_topic.example_topic.name
    GCP_PROJECT     = var.project_id
  }
}

# make http_handler function public
# TODO remove this, and use API Gateway in front of cloud function
resource "google_cloudfunctions_function_iam_member" "http_handler_invoker" {
  project        = google_cloudfunctions_function.http_handler_function.project
  region         = google_cloudfunctions_function.http_handler_function.region
  cloud_function = google_cloudfunctions_function.http_handler_function.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# VPC
resource "google_compute_network" "default" {
  name                    = "l7-xlb-network"
  provider                = google
  auto_create_subnetworks = false
}

# backend subnet
resource "google_compute_subnetwork" "default" {
  name          = "l7-xlb-subnet"
  provider      = google
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.default.id
}

# reserved IP address
resource "google_compute_global_address" "default" {
  name = "l7-xlb-static-ip"
}

# forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
  name                  = "l7-xlb-forwarding-rule"
  provider              = google
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}

# http proxy
resource "google_compute_target_http_proxy" "default" {
  name     = "l7-xlb-target-http-proxy"
  provider = google
  url_map  = google_compute_url_map.default.id
}

# url map
resource "google_compute_url_map" "default" {
  name     = "l7-xlb-url-map"
  provider = google

  # serve the ui by default
  default_service = google_compute_backend_bucket.ui_backend_bucket.id

  path_matcher {
    name = "mysite"

    path_rule {
      paths   = ["/read"]
      service = google_compute_backend_service.http_handler_function_backend_service.id
    }

    path_rule {
      paths   = ["/write"]
      service = google_compute_backend_service.http_handler_function_backend_service.id
    }

    # serve the ui by default
    default_service = google_compute_backend_bucket.ui_backend_bucket.id
  }

  host_rule {
    hosts        = ["*"]
    path_matcher = "mysite"
  }
}

# backend service with custom request and response headers
resource "google_compute_backend_service" "pubsub_function_backend_service" {
  name                  = "l7-xlb-backend-service-pubsub"
  provider              = google
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  backend {
    group           = google_compute_region_network_endpoint_group.pubsub_function_neg.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# serverless network endpoint group for pubsub function
resource "google_compute_region_network_endpoint_group" "pubsub_function_neg" {
  name                  = "pubsub-function-neg"
  network_endpoint_type = "SERVERLESS"
  region                = "us-central1"
  cloud_function {
    function = google_cloudfunctions_function.pubsub_function.name
  }
}

# backend service for http-handler function
resource "google_compute_backend_service" "http_handler_function_backend_service" {
  name                  = "l7-xlb-backend-service-http-handler"
  provider              = google
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  backend {
    group           = google_compute_region_network_endpoint_group.http_handler_function_neg.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# serverless network endpoint group for http-handler function
resource "google_compute_region_network_endpoint_group" "http_handler_function_neg" {
  name                  = "http-handler-function-neg"
  network_endpoint_type = "SERVERLESS"
  region                = "us-central1"
  cloud_function {
    function = google_cloudfunctions_function.http_handler_function.name
  }
}

# when you delete an instance, you can't reuse the name of the deleted instance until one week from the deletion date
resource "random_id" "db_name_suffix" {
  byte_length = 4
}

# cloud sql instance
resource "google_sql_database_instance" "db" {
  name                = "master-instance-${random_id.db_name_suffix.hex}"
  database_version    = "POSTGRES_13"
  region              = "us-central1"
  deletion_protection = false

  settings {
    # Second-generation instance tiers are based on the machine
    # type. See argument reference below.
    tier = "db-f1-micro"
  }
}

# create a database
resource "google_sql_database" "database" {
  name     = local.database_name
  instance = google_sql_database_instance.db.name
}

# create a user
resource "google_sql_user" "users" {
  name     = local.database_user
  instance = google_sql_database_instance.db.name
  password = local.database_password
}

output "master-db-connection-name" {
  value = google_sql_database_instance.db.connection_name
}

resource "google_pubsub_topic" "example_topic" {
  name = "example-topic"
}