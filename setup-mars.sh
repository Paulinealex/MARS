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
gcloud services disable dataflow.googleapis.com --force
gcloud services enable dataflow.googleapis.com

# Create service account
echo "Creating service account 'marssa'..."
gcloud iam service-accounts create marssa || true
sleep 1

# Grant IAM roles
echo "Granting IAM roles..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member "serviceAccount:marssa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role "roles/editor"
sleep 1

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member "serviceAccount:marssa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role "roles/dataflow.worker"
sleep 1

if [[ -n "${USER_EMAIL:-}" ]]; then
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member "user:${USER_EMAIL}" \
        --role "roles/iam.serviceAccountUser"
fi

# Create BigQuery datasets and tables with schema
echo "Creating BigQuery resources..."
bq mk mars || true
bq mk --schema timestamp:STRING,ipaddr:STRING,action:STRING,srcacct:STRING,destacct:STRING,amount:NUMERIC,customername:STRING -t mars.activities || true
bq mk --schema message:STRING -t mars.raw || true

# Create Pub/Sub resources
echo "Setting up Pub/Sub..."
gcloud pubsub topics create activities-topic || true
gcloud pubsub subscriptions create activities-subscription --topic activities-topic || true

echo "Setup complete!"
echo "You can now run:"
echo " - ./run-local.sh"
echo " - ./run-cloud.sh"
echo " - cd streaming && ./run-stream-local.sh"
echo " - cd streaming && ./run-stream-cloud.sh"