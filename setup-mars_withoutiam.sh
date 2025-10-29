#!/bin/bash
set -euo pipefail

PROJECT_ARG="${1:-}"
PROJECT_ID="${PROJECT_ARG:-${GOOGLE_CLOUD_PROJECT:-}}"

# try gcloud config if still empty (requires gcloud installed & authenticated)
if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi

# try metadata server (works on Cloud Shell / GCE / GKE)
if [[ -z "$PROJECT_ID" ]]; then
  if curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/project-id" >/tmp/_projid 2>/dev/null; then
    PROJECT_ID="$(cat /tmp/_projid 2>/dev/null || true)"
    rm -f /tmp/_projid
  fi
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "Project has not been set! Provide PROJECT_ID as first arg, set GOOGLE_CLOUD_PROJECT, or run 'gcloud config set project PROJECT_ID'."
  exit 1
fi
echo "Project Name: $PROJECT_ID"

echo "Project Name: $PROJECT_ID"

# Create bucket with soft delete disabled and handle existing-bucket case
echo "Creating GCS bucket..."
if gcloud storage buckets describe "gs://${PROJECT_ID}-bucket" >/dev/null 2>&1; then
    echo "VALIDATION: Bucket gs://${PROJECT_ID}-bucket already exists, skipping creation."
else
    if gcloud storage buckets create "gs://${PROJECT_ID}-bucket" --soft-delete-duration=0 2>/tmp/_gcs_create.err; then
        echo "OK: Created gs://${PROJECT_ID}-bucket"
    else
        errout="$(cat /tmp/_gcs_create.err 2>/dev/null || true)"
        rm -f /tmp/_gcs_create.err
        if echo "$errout" | grep -q "HTTPError 409"; then
            echo "NOTE: Your previous request to create the named bucket succeeded and you already own it."
        else
            echo "ERROR: Failed to create bucket gs://${PROJECT_ID}-bucket"
            echo "$errout"
            exit 1
        fi
    fi
fi

# Enable Dataflow API (best-effort in sandbox)
echo "Configuring Dataflow API..."
gcloud services disable dataflow.googleapis.com --force >/dev/null 2>&1 || true
gcloud services enable dataflow.googleapis.com >/dev/null 2>&1 || echo "WARN: Unable to enable Dataflow API (permissions may be restricted)"

# Create service account (idempotent)
# echo "Creating service account 'marssa'..."
# if gcloud iam service-accounts describe "marssa@${PROJECT_ID}.iam.gserviceaccount.com" >/dev/null 2>&1; then
#     echo "VALIDATION: Service account marssa already exists, skipping create."
# else
#     gcloud iam service-accounts create marssa >/dev/null 2>&1 && echo "OK: Service account marssa created." || echo "WARN: Could not create service account (insufficient permissions?)"
# fi

# Note about IAM permissions
#echo "Note: IAM permissions may be restricted in this environment."
#echo "In production, the service account typically needs: roles/editor, roles/dataflow.worker, roles/iam.serviceAccountUser"

# Create BigQuery dataset and tables (idempotent)
echo "Creating BigQuery resources..."
if bq show "${PROJECT_ID}:mars" >/dev/null 2>&1; then
    echo "VALIDATION: BigQuery dataset 'mars' already exists."
else
    bq mk --dataset --description "Dataset for MARS" "${PROJECT_ID}:mars" >/dev/null 2>&1 && echo "OK: Created BigQuery dataset 'mars'." || echo "WARN: Could not create BigQuery dataset 'mars' (permissions?)"
fi

bq mk --schema timestamp:STRING,ipaddr:STRING,action:STRING,srcacct:STRING,destacct:STRING,amount:NUMERIC,customername:STRING -t "${PROJECT_ID}:mars.activities" >/dev/null 2>&1 || echo "INFO: Table mars.activities exists or could not be created."
bq mk --schema message:STRING -t "${PROJECT_ID}:mars.raw" >/dev/null 2>&1 || echo "INFO: Table mars.raw exists or could not be created."

# Create Pub/Sub resources (idempotent)
echo "Setting up Pub/Sub..."

# Try to subscribe to the shared moonbank-mars topic first (if accessible)
echo "Attempting to subscribe to moonbank-mars topic..."
if gcloud pubsub subscriptions create mars-activities --topic projects/moonbank-mars/topics/activities 2>/dev/null; then
    echo "OK: Subscribed to shared moonbank-mars topic via mars-activities subscription"
else
    echo "Note: Could not access moonbank-mars topic. Creating local topic and subscription..."
    
    # Create local topic if moonbank-mars is not accessible
    gcloud pubsub topics describe activities-topic >/dev/null 2>&1 || gcloud pubsub topics create activities-topic >/dev/null 2>&1 && echo "OK: activities-topic created."
    
    # Create activities-subscription pointing to local topic
    gcloud pubsub subscriptions describe activities-subscription >/dev/null 2>&1 || gcloud pubsub subscriptions create activities-subscription --topic activities-topic >/dev/null 2>&1 && echo "OK: activities-subscription created."
fi

echo "Setup complete with limited permissions!"
echo "Note: Some operations may fail due to sandbox restrictions."
# echo ""
# echo "Starting MARS local processing pipeline..."

# # Executing the first script run-local.sh
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# bash "${SCRIPT_DIR}/run-local.sh"

# # --- Automated post-run validations (best-effort; does not abort on failures) ---
# echo ""
# echo "Running post-run validations..."
# set +e
# FAILS=0

# # 1) Validate local output produced
# if [ -d "${SCRIPT_DIR}/output" ] && [ "$(ls -A "${SCRIPT_DIR}/output" 2>/dev/null)" ]; then
#     echo "VALIDATION: Local output directory exists and is not empty."
# else
#     echo "VALIDATION FAILED: Local output missing or empty."
#     FAILS=$((FAILS+1))
# fi

# # 2) Validate files uploaded to GCS bucket/local/
# if gcloud storage ls "gs://${PROJECT_ID}-bucket/local/" >/dev/null 2>&1; then
#     count=$(gcloud storage ls "gs://${PROJECT_ID}-bucket/local/" --format="value(name)" 2>/dev/null | wc -l)
#     if [ "${count}" -gt 0 ]; then
#         echo "VALIDATION: GCS upload succeeded — ${count} objects found in gs://${PROJECT_ID}-bucket/local/."
#     else
#         echo "VALIDATION WARNING: GCS path exists but contains no objects."
#         FAILS=$((FAILS+1))
#     fi
# else
#     echo "VALIDATION WARNING: Unable to list gs://${PROJECT_ID}-bucket/local/ (may not exist or permission denied)."
#     FAILS=$((FAILS+1))
# fi

# # 3) Validate BigQuery table and row count (best-effort)
# if bq --project_id="${PROJECT_ID}" show --format=prettyjson "${PROJECT_ID}:mars.activities" >/dev/null 2>&1; then
#     rows=$(bq --project_id="${PROJECT_ID}" query --nouse_legacy_sql --format=csv "SELECT COUNT(*) FROM \`${PROJECT_ID}.mars.activities\`" 2>/dev/null | tail -n1)
#     if [[ "${rows}" == "" ]]; then
#         echo "VALIDATION: BigQuery table exists but row count could not be determined."
#     else
#         echo "VALIDATION: BigQuery table mars.activities exists — row count: ${rows}"
#     fi
# else
#     echo "VALIDATION WARNING: BigQuery table mars.activities not accessible or missing."
#     FAILS=$((FAILS+1))
# fi

# # Summary of automated validations
# if [ "${FAILS}" -eq 0 ]; then
#     echo ""
#     echo "All automated post-run validations passed."
# else
#     echo ""
#     echo "Automated post-run validations completed with ${FAILS} issues reported."
# fi
# set -e

# # --- First-run GUI checklist specific to run-local.sh ---
# cat <<EOF

# First-run GUI Validation Checklist (manual)
# Please verify these items in the Cloud Console for the first run of run-local.sh:

# 1) GCS upload
#    - Confirm objects exist at: gs://${PROJECT_ID}-bucket/local/
#      Console URL:
#      https://console.cloud.google.com/storage/browser/${PROJECT_ID}-bucket/local/?project=${PROJECT_ID}

# 2) BigQuery load
#    - Confirm table 'mars.activities' exists and contains rows:
#      Console URL:
#      https://console.cloud.google.com/bigquery?project=${PROJECT_ID}

# After checking the 3 items above in the Console, confirm below to continue.
# EOF

# # prompt and wait for user confirmation (manual GUI checks)
# while true; do
#     read -r -p "Have you verified the first-run GUI checklist items above? (y/n): " RESP2
#     case "$RESP2" in
#         [Yy]) echo "User confirmed GUI validations."; break ;;
#         [Nn]) echo "Please complete the GUI checks and re-run this script when ready."; exit 0 ;;
#         *) echo "Please answer y or n." ;;
#     esac
# done

# echo ""
# # Executing the batch cloud script
# echo " Starting MARS cloud processing pipeline..."
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# bash "${SCRIPT_DIR}/run-cloud.sh"

echo ""
# Executing the streaming local script
echo " Starting MARS cloud processing pipeline..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/streaming/run-stream-local.sh"

# echo ""
# # Executing the streaming cloud script
# echo " Starting MARS cloud processing pipeline..."
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# bash "${SCRIPT_DIR}/streaming/run-stream-cloud.sh"