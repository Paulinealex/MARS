# MAKE SURE GCP PROJECT IS SET
# gcloud config set project PROJECT_ID
echo $GOOGLE_CLOUD_PROJECT

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Python dependencies..."
LOG="/tmp/mars-pip-install.log"
sudo pip3 install -q -r requirements.txt >"$LOG" 2>&1 || {
  echo "ERROR: pip install failed — showing last 100 lines of $LOG"
  tail -n 100 "$LOG"
  exit 1
}
rm -R output

# Use absolute path to run the Python script
python3 "${SCRIPT_DIR}/mars-stream-local.py"

echo ""
echo "Waiting 10 seconds for streaming pipeline to initialize..."
sleep 10

echo ""
echo "Publishing sample banking activity data..."
bash "${SCRIPT_DIR}/streaming/publish-sample-data.sh" 20

echo ""
echo "============================================================"
echo "✓ Sample data published successfully!"
echo "============================================================"
echo ""
echo "Streaming pipeline is running in background (PID: ${STREAM_LOCAL_PID})"
echo "Messages are being processed and written to BigQuery tables."
echo ""
echo "============================================================"
echo "Validation Resources - Verify data in:"
echo ""
echo "1. Pub/Sub Topic (activities-topic):"
echo "   https://console.cloud.google.com/cloudpubsub/topic/detail/activities-topic?project=${PROJECT_ID}"
echo ""
echo "2. Pub/Sub Subscription (activities-subscription):"
echo "   https://console.cloud.google.com/cloudpubsub/subscription/detail/activities-subscription?project=${PROJECT_ID}"
echo ""
echo "3. BigQuery Table - mars.raw (raw messages):"
echo "   https://console.cloud.google.com/bigquery?project=${PROJECT_ID}&ws=!1m5!1m4!4m3!1s${PROJECT_ID}!2smars!3sraw"
echo ""
echo "4. BigQuery Table - mars.activities (structured data):"
echo "   https://console.cloud.google.com/bigquery?project=${PROJECT_ID}&ws=!1m5!1m4!4m3!1s${PROJECT_ID}!2smars!3sactivities"
echo ""
echo "============================================================"
echo ""
echo "To publish more messages:"
echo "  bash streaming/publish-sample-data.sh [NUM_MESSAGES]"
echo ""
echo "To stop the streaming pipeline:"
echo "  kill ${STREAM_LOCAL_PID}"
echo "  (Or press Ctrl+C in the streaming terminal)"
echo ""
echo "============================================================"
echo "✓ MARS setup and initial streaming completed!"
echo "============================================================"
echo ""
# Prompt for validation confirmation before proceeding to cloud streaming
echo "============================================================"
while true; do
    read -r -p "Have you verified the streaming data in BigQuery tables? (y/n): " VALIDATION_RESPONSE
    case "$VALIDATION_RESPONSE" in
        [Yy]* ) 
            echo "✓ Validation confirmed. Proceeding to cloud streaming..."
            break 
            ;;
        [Nn]* ) 
            echo "⚠ Validation not confirmed. Please check the BigQuery tables above."
            echo "You can still proceed, but please verify the data."
            read -r -p "Do you want to proceed anyway? (y/n): " PROCEED_ANYWAY
            case "$PROCEED_ANYWAY" in
                [Yy]* ) 
                    echo "Proceeding to cloud streaming..."
                    break 
                    ;;
                [Nn]* ) 
                    echo "Exiting. Run the cloud streaming manually when ready:"
                    echo "  bash streaming/run-stream-cloud.sh"
                    exit 0 
                    ;;
                * ) 
                    echo "Please answer y or n." 
                    ;;
            esac
            ;;
        * ) 
            echo "Please answer y or n." 
            ;;
    esac
done
echo "============================================================"
