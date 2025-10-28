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
read -p "Wait for Dataflow Job to Finish and then press enter"
bq load mars.activities gs://"$GOOGLE_CLOUD_PROJECT""-bucket"/output/output*