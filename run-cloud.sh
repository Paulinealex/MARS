# MAKE SURE GCP PROJECT IS SET
# gcloud config set project PROJECT_ID
echo $GOOGLE_CLOUD_PROJECT
gcloud services enable dataflow.googleapis.com

echo "Installing Python dependencies..."
LOG="/tmp/mars-pip-install.log"
sudo pip3 install -q -r requirements.txt >"$LOG" 2>&1 || {
  echo "ERROR: pip install failed — showing last 100 lines of $LOG"
  tail -n 100 "$LOG"
  exit 1
}
python3 mars-cloud.py 

echo ""
echo "Monitor your Dataflow job status here:"
echo "https://console.cloud.google.com/dataflow/jobs?project=$GOOGLE_CLOUD_PROJECT"
echo ""

read -p "Wait for Dataflow Job to Finish and then press enter"

echo ""
echo "Loading data into BigQuery table mars.activities..."
bq load mars.activities gs://"$GOOGLE_CLOUD_PROJECT""-bucket"/output/output*

echo ""
echo "✓ Data loaded successfully!"
echo ""
echo "Querying mars.activities table to view sample data:"
echo ""
bq query --nouse_legacy_sql "SELECT * FROM \`$GOOGLE_CLOUD_PROJECT.mars.activities\` LIMIT 10"

echo ""
echo "View the full data in BigQuery:"
echo "https://console.cloud.google.com/bigquery?project=$GOOGLE_CLOUD_PROJECT&ws=!1m5!1m4!4m3!1s$GOOGLE_CLOUD_PROJECT!2smars!3sactivities"
echo ""
echo "============================================================"
read -p "Validation completed? Have you verified the data in BigQuery? (y/n): " VALIDATION_RESPONSE

case "$VALIDATION_RESPONSE" in
    [Yy]* ) 
        echo "✓ Validation confirmed. Proceeding..."
        ;;
    [Nn]* ) 
        echo "⚠ Validation not confirmed. Please check the BigQuery table and Dataflow job logs."
        echo "Exiting without proceeding."
        exit 0
        ;;
    * ) 
        echo "Invalid response. Exiting."
        exit 1
        ;;
esac
echo "============================================================"
echo ""