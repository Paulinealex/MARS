#!/bin/bash
# Script to publish sample banking activity messages to Pub/Sub topic
# These messages will be consumed by the streaming pipeline and written to BigQuery

set -euo pipefail

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "ERROR: Project not set. Run 'gcloud config set project PROJECT_ID' or set GOOGLE_CLOUD_PROJECT"
  exit 1
fi

TOPIC_NAME="activities-topic"
NUM_MESSAGES="${1:-10}"  # Default to 10 messages, or use first argument

echo "Publishing ${NUM_MESSAGES} sample messages to topic: ${TOPIC_NAME}"
echo "Project: ${PROJECT_ID}"
echo "Messages will be consumed by streaming pipeline and written to mars.activities table"
echo ""

# Sample data arrays
ACTIONS=("login" "transfer" "deposit" "withdrawal" "payment" "logout")
CUSTOMERS=("Alice Johnson" "Bob Smith" "Carol White" "David Brown" "Eve Davis" "Frank Miller")
SOURCE_ACCOUNTS=("ACC001" "ACC002" "ACC003" "ACC004" "ACC005" "ACC006")
DEST_ACCOUNTS=("ACC101" "ACC102" "ACC103" "ACC104" "ACC105" "ACC106")
IP_ADDRESSES=("192.168.1.100" "10.0.0.50" "172.16.0.25" "192.168.2.75" "10.1.1.200")

# Function to generate random amount between 10 and 10000
generate_amount() {
  echo "$(( RANDOM % 9991 + 10 ))"
}

# Function to get random element from array
get_random() {
  local arr=("$@")
  local idx=$(( RANDOM % ${#arr[@]} ))
  echo "${arr[$idx]}"
}

# Publish messages in a loop
for i in $(seq 1 "$NUM_MESSAGES"); do
  # Generate timestamp (current time in ISO format)
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
  
  # Generate random data
  ACTION=$(get_random "${ACTIONS[@]}")
  CUSTOMER=$(get_random "${CUSTOMERS[@]}")
  SRC_ACCT=$(get_random "${SOURCE_ACCOUNTS[@]}")
  DEST_ACCT=$(get_random "${DEST_ACCOUNTS[@]}")
  IP_ADDR=$(get_random "${IP_ADDRESSES[@]}")
  AMOUNT=$(generate_amount)
  
  # Create CSV message (matching mars.activities schema)
  MESSAGE="${TIMESTAMP},${IP_ADDR},${ACTION},${SRC_ACCT},${DEST_ACCT},${AMOUNT},${CUSTOMER}"
  
  # Publish to Pub/Sub
  if gcloud pubsub topics publish "${TOPIC_NAME}" --message "${MESSAGE}" >/dev/null 2>&1; then
    echo "[$i/${NUM_MESSAGES}] Published: ${ACTION} by ${CUSTOMER} - Amount: \$${AMOUNT}"
  else
    echo "[$i/${NUM_MESSAGES}] FAILED to publish message"
  fi
  
  # Small delay between messages (0.5 seconds)
  sleep 0.5
done

echo ""
echo "✓ Successfully published ${NUM_MESSAGES} messages to ${TOPIC_NAME}"
echo ""
echo "View messages in BigQuery:"
echo "  https://console.cloud.google.com/bigquery?project=${PROJECT_ID}&ws=!1m5!1m4!4m3!1s${PROJECT_ID}!2smars!3sactivities"
echo ""
echo "Run query to see latest messages:"
echo "  bq query --nouse_legacy_sql 'SELECT * FROM \`${PROJECT_ID}.mars.activities\` ORDER BY timestamp DESC LIMIT 10'"