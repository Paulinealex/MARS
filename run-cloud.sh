# MAKE SURE GCP PROJECT IS SET
# gcloud config set project PROJECT_ID
echo $GOOGLE_CLOUD_PROJECT

# Define and setup service account permissions
COMPUTE_SA="${GOOGLE_CLOUD_PROJECT}-compute@developer.gserviceaccount.com"
echo "Setting up Compute Engine service account: ${COMPUTE_SA}"

# Grant necessary roles to Compute Engine service account
echo "Adding IAM bindings..."
gcloud projects add-iam-policy-binding "${GOOGLE_CLOUD_PROJECT}" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/dataflow.worker" || echo "Warning: Could not add dataflow.worker role"
sleep 1

gcloud projects add-iam-policy-binding "${GOOGLE_CLOUD_PROJECT}" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/bigquery.dataEditor" || echo "Warning: Could not add bigquery.dataEditor role"
sleep 1

gcloud projects add-iam-policy-binding "${GOOGLE_CLOUD_PROJECT}" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/storage.objectViewer" || echo "Warning: Could not add storage.objectViewer role"
sleep 1

# Grant current user permission to act as the service account
USER_EMAIL=$(gcloud config get-value account)
if [[ -n "${USER_EMAIL}" ]]; then
    echo "Granting serviceAccountUser role to ${USER_EMAIL}"
    gcloud projects add-iam-policy-binding "${GOOGLE_CLOUD_PROJECT}" \
        --member="user:${USER_EMAIL}" \
        --role="roles/iam.serviceAccountUser" || echo "Warning: Could not add iam.serviceAccountUser role"
fi

# Enable Dataflow API
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