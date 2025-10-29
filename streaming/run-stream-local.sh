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