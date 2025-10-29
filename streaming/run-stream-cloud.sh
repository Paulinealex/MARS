#!/bin/bash

# MAKE SURE GCP PROJECT IS SET
# gcloud config set project PROJECT_ID
echo $GOOGLE_CLOUD_PROJECT

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Python dependencies..."
LOG="/tmp/mars-pip-install.log"
sudo pip3 install -q -r "${SCRIPT_DIR}/../requirements.txt" >"$LOG" 2>&1 || {
  echo "ERROR: pip install failed — showing last 100 lines of $LOG"
  tail -n 100 "$LOG"
  exit 1
}

python3 "${SCRIPT_DIR}/mars-stream-cloud.py"

echo ""
echo "Waiting 30 seconds for Dataflow job to initialize..."
sleep 30

echo ""
echo "Publishing sample banking activity data to test Dataflow pipeline..."
bash "${SCRIPT_DIR}/publish-sample-data.sh" 20

echo ""
echo "============================================================"
echo "✓ Sample data published successfully!"
echo "============================================================"
echo ""
echo "Dataflow streaming job is now running on Google Cloud."
echo "Messages are being processed and written to BigQuery tables."
echo ""
echo "============================================================"
echo "Validation Resources - Verify data in:"
echo ""
echo "1. Dataflow Job (monitor streaming pipeline):"
echo "   https://console.cloud.google.com/dataflow/jobs?project=${projectname}"
echo ""
echo "2. Pub/Sub Topic (activities-topic):"
echo "   https://console.cloud.google.com/cloudpubsub/topic/detail/activities-topic?project=${projectname}"
echo ""
echo "3. Pub/Sub Subscription (activities-subscription):"
echo "   https://console.cloud.google.com/cloudpubsub/subscription/detail/activities-subscription?project=${projectname}"
echo ""
echo "4. BigQuery Table - mars.raw (raw messages):"
echo "   https://console.cloud.google.com/bigquery?project=${projectname}&ws=!1m5!1m4!4m3!1s${projectname}!2smars!3sraw"
echo ""
echo "5. BigQuery Table - mars.activities (structured data):"
echo "   https://console.cloud.google.com/bigquery?project=${projectname}&ws=!1m5!1m4!4m3!1s${projectname}!2smars!3sactivities"
echo ""
echo "============================================================"
echo ""
echo "To publish more messages:"
echo "  bash streaming/publish-sample-data.sh [NUM_MESSAGES]"
echo ""
echo "To stop the Dataflow job:"
echo "  - Go to Dataflow Console and drain/cancel the job"
echo "  - Or use: gcloud dataflow jobs cancel JOB_ID --region=us-central1"
echo ""
echo "============================================================"
echo "✓ MARS cloud streaming pipeline setup completed!"
echo "============================================================"
echo ""