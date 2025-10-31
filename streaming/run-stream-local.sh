#!/bin/bash

# MAKE SURE GCP PROJECT IS SET
# gcloud config set project PROJECT_ID
projectname="${GOOGLE_CLOUD_PROJECT}"
echo "Starting MARS local streaming pipeline..."
echo "Project: ${projectname}"

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "Installing Python dependencies..."
LOG="/tmp/mars-pip-install.log"
sudo pip3 install -q -r "${SCRIPT_DIR}/../requirements.txt" >"$LOG" 2>&1 || {
  echo "ERROR: pip install failed — showing last 100 lines of $LOG"
  tail -n 100 "$LOG"
  exit 1
}

echo ""
echo "Starting local streaming pipeline in background..."
# Start streaming pipeline in background
python3 "${SCRIPT_DIR}/mars-stream-local.py" &
STREAM_PID=$!

echo ""
echo "Waiting 10 seconds for streaming pipeline to initialize..."
sleep 10

echo ""
echo "Publishing sample banking activity data..."
bash "${SCRIPT_DIR}/publish-sample-data.sh" 20

echo ""
echo "============================================================"
echo "✓ Sample data published successfully!"
echo "============================================================"
echo ""
echo "Streaming pipeline is running in background (PID: ${STREAM_PID})"
echo "Messages are being processed and written to BigQuery tables."
echo ""
echo "============================================================"
echo "Validation Resources - Verify data in:"
echo ""
echo "1. Pub/Sub Topic (activities-topic):"
echo "   https://console.cloud.google.com/cloudpubsub/topic/detail/activities-topic?project=${projectname}"
echo ""
echo "2. Pub/Sub Subscription (activities-subscription):"
echo "   https://console.cloud.google.com/cloudpubsub/subscription/detail/activities-subscription?project=${projectname}"
echo ""
echo "3. BigQuery Table - mars.raw (raw messages):"
echo "   https://console.cloud.google.com/bigquery?project=${projectname}&ws=!1m5!1m4!4m3!1s${projectname}!2smars!3sraw"
echo ""
echo "4. BigQuery Table - mars.activities (structured data):"
echo "   https://console.cloud.google.com/bigquery?project=${projectname}&ws=!1m5!1m4!4m3!1s${projectname}!2smars!3sactivities"
echo ""
echo "============================================================"
echo ""
echo "To publish more messages:"
echo "  bash streaming/publish-sample-data.sh [NUM_MESSAGES]"
echo ""
echo "To stop the streaming pipeline:"
echo "  kill ${STREAM_PID}"
echo "  (Or press Ctrl+C if running in foreground)"
echo ""
echo "============================================================"
echo "✓ MARS local streaming pipeline setup completed!"
echo "============================================================"
echo ""

# Wait for user to review before exiting
echo "Press Ctrl+C to stop, or the script will exit and leave streaming running in background."
sleep 5