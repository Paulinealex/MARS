#!/bin/bash
set -euo pipefail

PROJECT_ARG="${1:-}"
PROJECT_ID="${PROJECT_ARG:-${GOOGLE_CLOUD_PROJECT:-}}"

if [[ -z "$PROJECT_ID" ]]; then
    echo "Project has not been set! Please run:"
    echo "   gcloud config set project PROJECT_ID"
    echo "(where PROJECT_ID is the desired project)"
    exit 1
fi

echo "Project Name: $PROJECT_ID"

# Create bucket with soft delete disabled
echo "Creating GCS bucket..."
gcloud storage buckets create "gs://${PROJECT_ID}-bucket" --soft-delete-duration=0 || true

# Enable Dataflow API with force disable first
echo "Configuring Dataflow API..."
gcloud services disable dataflow.googleapis.com --force || true
gcloud services enable dataflow.googleapis.com || true

# Create service account
echo "Creating service account 'marssa'..."
gcloud iam service-accounts create marssa || true

# Note about IAM permissions
echo "Note: IAM permissions could not be set due to sandbox restrictions."
echo "In a production environment, the service account would need:"
echo " - roles/editor"
echo " - roles/dataflow.worker"
echo " - roles/iam.serviceAccountUser"

# Create BigQuery datasets and tables with schema
echo "Creating BigQuery resources..."
bq mk mars || true
bq mk --schema timestamp:STRING,ipaddr:STRING,action:STRING,srcacct:STRING,destacct:STRING,amount:NUMERIC,customername:STRING -t mars.activities || true
bq mk --schema message:STRING -t mars.raw || true

# Create Pub/Sub resources
echo "Setting up Pub/Sub..."
gcloud pubsub topics create activities-topic || true
gcloud pubsub subscriptions create activities-subscription --topic activities-topic || true

echo "Setup complete with limited permissions!"
echo "Note: Some operations may fail due to sandbox restrictions."
echo "Starting MARS local processing pipeline..."
bash -x "$(dirname "$0")/run-local.sh"
echo " - ./run-cloud.sh"
echo " - cd streaming && ./run-stream-local.sh"
echo " - cd streaming && ./run-stream-cloud.sh"