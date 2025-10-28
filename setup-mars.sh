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
SERVICE_ACCOUNT="mars-service-account"  # Updated service account name
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
USER_EMAIL="${USER_EMAIL:-}"

echo "Setting up MARS environment for project: ${PROJECT_ID}"

gcloud config set project "${PROJECT_ID}"

echo "Creating GCS bucket: gs://${BUCKET_NAME}"
gcloud storage buckets create "gs://${BUCKET_NAME}" --soft-delete-duration=0 || true

echo "Enabling Dataflow API..."
gcloud services enable dataflow.googleapis.com

echo "Creating service account '${SERVICE_ACCOUNT}' if it does not exist..."
if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SERVICE_ACCOUNT}"
else
  echo "Service account ${SERVICE_ACCOUNT_EMAIL} already exists, skipping create."
fi

# Grant BigQuery Data Editor role to the service account
echo "Granting BigQuery Data Editor role to ${SERVICE_ACCOUNT_EMAIL}..."
bq mk --dataset --description "Dataset for MARS" "${PROJECT_ID}:mars" || true

# Create a temporary IAM policy file
IAM_POLICY_FILE=$(mktemp)
cat <<EOF > "${IAM_POLICY_FILE}"
{
  "bindings": [
    {
      "role": "roles/bigquery.dataEditor",
      "members": [
        "serviceAccount:${SERVICE_ACCOUNT_EMAIL}"
      ]
    }
  ]
}
EOF

# Update the IAM policy for the dataset
bq update --iam-policy "${PROJECT_ID}:mars" "${IAM_POLICY_FILE}"

# Clean up the temporary IAM policy file
rm "${IAM_POLICY_FILE}"

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

# ...existing code for BigQuery and Pub/Sub...

echo "Setup complete."
echo "Next steps:"
echo " - ./run-local.sh"
echo " - ./run-cloud.sh"
echo " - cd streaming && ./run-stream-local.sh"
echo " - cd streaming && ./run-stream-cloud.sh"