#!/bin/bash
set -euo pipefail

PROJECT="${1:-${GOOGLE_CLOUD_PROJECT:-}}"
if [[ -z "$PROJECT" ]]; then
  echo "Usage: $0 PROJECT_ID (or set GOOGLE_CLOUD_PROJECT)"
  exit 1
fi

BUCKET="${PROJECT}-bucket"
SA="marssa@${PROJECT}.iam.gserviceaccount.com"
USER_EMAIL="${USER_EMAIL:-}"

FAIL=0
function ok { echo "OK: $1"; }
function warn { echo "WARN: $1"; }
function fail { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# 1) gcloud project
if [[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT" ]]; then ok "gcloud project is set to $PROJECT"; else fail "gcloud project not set to $PROJECT"; fi

# 2) GCS bucket
if gcloud storage buckets describe "gs://${BUCKET}" >/dev/null 2>&1; then ok "Bucket gs://${BUCKET} exists"; else fail "Bucket gs://${BUCKET} missing"; fi

# 3) Dataflow API
if gcloud services list --enabled --filter="name:dataflow.googleapis.com" --format="value(name)" | grep -q "dataflow.googleapis.com"; then ok "Dataflow API enabled"; else fail "Dataflow API not enabled"; fi

# 4) Service account
if gcloud iam service-accounts describe "$SA" >/dev/null 2>&1; then ok "Service account $SA exists"; else fail "Service account $SA missing"; fi

# 5) IAM bindings for service account
for role in roles/editor roles/dataflow.worker; do
  if gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[]" --filter="bindings.role=${role}" --format='value(bindings.members)' | grep -q "serviceAccount:${SA}"; then ok "$role bound to $SA"; else fail "$role NOT bound to $SA"; fi
done

# 6) optional serviceAccountUser for USER_EMAIL
if [[ -n "$USER_EMAIL" ]]; then
  if gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[]" --filter="bindings.role=roles/iam.serviceAccountUser" --format='value(bindings.members)' | grep -q "user:${USER_EMAIL}"; then ok "roles/iam.serviceAccountUser bound to ${USER_EMAIL}"; else fail "roles/iam.serviceAccountUser NOT bound to ${USER_EMAIL}"; fi
else
  warn "USER_EMAIL not set; skipped serviceAccountUser check"
fi

# 7) BigQuery dataset and tables
if bq --project_id="$PROJECT" show --format=prettyjson "${PROJECT}:mars" >/dev/null 2>&1; then ok "BigQuery dataset 'mars' exists"; else fail "BigQuery dataset 'mars' missing"; fi
for tbl in activities raw; do
  if bq --project_id="$PROJECT" show --format=prettyjson "mars.${tbl}" >/dev/null 2>&1; then ok "Table mars.${tbl} exists"; else fail "Table mars.${tbl} missing"; fi
done

# 8) Pub/Sub topic and subscriptions
if gcloud pubsub topics describe activities-topic >/dev/null 2>&1; then ok "Pub/Sub topic 'activities-topic' exists"; else fail "Pub/Sub topic 'activities-topic' missing"; fi
for sub in activities-subscription mars-activities; do
  if gcloud pubsub subscriptions describe "$sub" >/dev/null 2>&1; then ok "Subscription '$sub' exists"; else fail "Subscription '$sub' missing"; fi
done

# Summary
if [[ "$FAIL" -eq 0 ]]; then
  echo "All checks passed."
  exit 0
else
  echo "$FAIL checks failed."
  exit 2
fi