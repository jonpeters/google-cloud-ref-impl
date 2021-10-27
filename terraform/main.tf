locals {
  project_id               = "before-commit"
  temp_storage_bucket_name = "temp-bucket-please-delete-me-121212"
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

  project = local.project_id
  region  = "us-central1"
  zone    = "us-central1-a"
}

# bucket to store deployment artifcats; e.g. cloud function zip packages
resource "google_storage_bucket" "bucket" {
  name = local.temp_storage_bucket_name
}

# zip file for writer function
resource "google_storage_bucket_object" "writer_archive" {
  name   = "writer.zip"
  bucket = google_storage_bucket.bucket.name
  source = "../src/cloud-functions/writer/writer.zip"
}

# zip file for reader function
resource "google_storage_bucket_object" "reader_archive" {
  name   = "reader.zip"
  bucket = google_storage_bucket.bucket.name
  source = "../src/cloud-functions/reader/reader.zip"
}

# create the writer cloud function
resource "google_cloudfunctions_function" "writer_function" {
  name        = "writer-function"
  description = "Writer Function"
  runtime     = "nodejs14"

  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.writer_archive.name
  trigger_http          = true
  entry_point           = "writer"

  environment_variables = {
    PROJECT_ID = local.project_id
  }
}

# make writer function public
# TODO remove this, and use API Gateway in front of cloud function
resource "google_cloudfunctions_function_iam_member" "writer_invoker" {
  project        = google_cloudfunctions_function.writer_function.project
  region         = google_cloudfunctions_function.writer_function.region
  cloud_function = google_cloudfunctions_function.writer_function.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# create the reader cloud function
resource "google_cloudfunctions_function" "reader_function" {
  name        = "reader-function"
  description = "Reader Function"
  runtime     = "nodejs14"

  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.reader_archive.name
  trigger_http          = true
  entry_point           = "reader"
}

# make reader function public
# TODO remove this, and use API Gateway in front of cloud function
resource "google_cloudfunctions_function_iam_member" "reader_invoker" {
  project        = google_cloudfunctions_function.reader_function.project
  region         = google_cloudfunctions_function.reader_function.region
  cloud_function = google_cloudfunctions_function.reader_function.name

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
  name            = "l7-xlb-url-map"
  provider        = google
  default_service = google_compute_backend_service.reader_function_backend_service.id

  path_matcher {
    name = "mysite"

    path_rule {
      paths   = ["/read"]
      service = google_compute_backend_service.reader_function_backend_service.id
    }

    path_rule {
      paths   = ["/write"]
      service = google_compute_backend_service.writer_function_backend_service.id
    }

    default_service = google_compute_backend_service.reader_function_backend_service.id
  }

  host_rule {
    hosts        = ["*"]
    path_matcher = "mysite"
  }
}

# backend service with custom request and response headers
resource "google_compute_backend_service" "writer_function_backend_service" {
  name                  = "l7-xlb-backend-service-writer"
  provider              = google
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  backend {
    group           = google_compute_region_network_endpoint_group.writer_function_neg.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# serverless network endpoint group for writer function
resource "google_compute_region_network_endpoint_group" "writer_function_neg" {
  name                  = "writer-function-neg"
  network_endpoint_type = "SERVERLESS"
  region                = "us-central1"
  cloud_function {
    function = google_cloudfunctions_function.writer_function.name
  }
}

# backend servic for reader function
resource "google_compute_backend_service" "reader_function_backend_service" {
  name                  = "l7-xlb-backend-service-reader"
  provider              = google
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  backend {
    group           = google_compute_region_network_endpoint_group.reader_function_neg.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# serverless network endpoint group for reader function
resource "google_compute_region_network_endpoint_group" "reader_function_neg" {
  name                  = "reader-function-neg"
  network_endpoint_type = "SERVERLESS"
  region                = "us-central1"
  cloud_function {
    function = google_cloudfunctions_function.reader_function.name
  }
}
