#!/bin/bash
set -euo pipefail

# ...existing code...

# Usage: ./setup-mars.sh [PROJECT_ID]
# If PROJECT_ID not passed, falls back to $GOOGLE_CLOUD_PROJECT if set.

PROJECT_ARG="${1:-}"
PROJECT_ID="${PROJECT_ARG:-${GOOGLE_CLOUD_PROJECT:-}}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "Project not provided. Use: ./setup-mars.sh PROJECT_ID or set GOOGLE_CLOUD_PROJECT env var."
  exit 1
fi

BUCKET_NAME="${PROJECT_ID}-bucket"
SERVICE_ACCOUNT="marssa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
USER_EMAIL="${USER_EMAIL:-}"

echo "Setting up MARS environment for project: ${PROJECT_ID}"

gcloud config set project "${PROJECT_ID}"

echo "Creating GCS bucket: gs://${BUCKET_NAME}"
# use gcloud storage create with soft-delete disabled (as in prep-project.sh)
gcloud storage buckets create "gs://${BUCKET_NAME}" --soft-delete-duration=0 || true

echo "Enabling Dataflow API..."
gcloud services enable dataflow.googleapis.com

echo "Creating service account '${SERVICE_ACCOUNT}' if it does not exist..."
if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SERVICE_ACCOUNT}"
else
  echo "Service account ${SERVICE_ACCOUNT_EMAIL} already exists, skipping create."
fi

echo "Granting IAM roles to ${SERVICE_ACCOUNT_EMAIL}..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role "roles/editor"
sleep 1

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role "roles/dataflow.worker"
sleep 1

if [[ -n "${USER_EMAIL}" ]]; then
  echo "Granting roles/iam.serviceAccountUser to ${USER_EMAIL} for ${SERVICE_ACCOUNT_EMAIL}..."
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member "user:${USER_EMAIL}" \
    --role "roles/iam.serviceAccountUser"
else
  echo "USER_EMAIL not set; skipping roles/iam.serviceAccountUser binding. To add, set USER_EMAIL env var."
fi

echo "Creating BigQuery dataset and tables..."
if ! bq --project_id="${PROJECT_ID}" show --format=prettyjson "${PROJECT_ID}:mars" >/dev/null 2>&1; then
  bq mk --project_id="${PROJECT_ID}" mars
else
  echo "BigQuery dataset 'mars' already exists, skipping."
fi

bq mk --schema timestamp:STRING,ipaddr:STRING,action:STRING,srcacct:STRING,destacct:STRING,amount:NUMERIC,customername:STRING -t mars.activities || true
bq mk --schema message:STRING -t mars.raw || true

echo "Creating Pub/Sub topic/subscription (if not present)..."
if ! gcloud pubsub topics describe activities-topic >/dev/null 2>&1; then
  gcloud pubsub topics create activities-topic
else
  echo "Topic activities-topic already exists."
fi

if ! gcloud pubsub subscriptions describe activities-subscription >/dev/null 2>&1; then
  gcloud pubsub subscriptions create activities-subscription --topic=activities-topic
else
  echo "Subscription activities-subscription already exists."
fi

# Ensure streaming pipeline subscription name expected by mars-stream-local.py exists
if ! gcloud pubsub subscriptions describe mars-activities >/dev/null 2>&1; then
  echo "Creating subscription 'mars-activities' (alias for streaming)..."
  gcloud pubsub subscriptions create mars-activities --topic=activities-topic
else
  echo "Subscription mars-activities already exists."
fi

echo "Setup complete."
echo "Next steps:"
echo " - ./run-local.sh"
echo " - ./run-cloud.sh"
echo " - cd streaming && ./run-stream-local.sh"
echo " - cd streaming && ./run-stream-cloud.sh"