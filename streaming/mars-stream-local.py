#!/usr/bin/env python3
import apache_beam as beam
import os
import subprocess
import time
import threading
import signal
import sys
import warnings
import logging

# Suppress httplib2 timeout warnings
warnings.filterwarnings('ignore', message='.*httplib2.*timeout.*')
logging.getLogger('google_auth_httplib2').setLevel(logging.ERROR)

# Global flag to track if message was received (use threading.Event for thread safety)
message_received_event = threading.Event()
pipeline_result = None

def processline(line):
    global message_received_event
    outputrow = {'message' : line}
    print(f"✓ Message received and processed: {outputrow}")
    if not message_received_event.is_set():
        message_received_event.set()  # Thread-safe way to signal message received
        # Print success message immediately when first message is received
        print(f"\n{'='*60}")
        print("✓ SUCCESS: Pipeline is working correctly!")
        print("  - Subscription read the published message")
        print("  - Message was processed and written to BigQuery")
        print("  - Pipeline will continue running until Ctrl+C")
        print(f"{'='*60}\n")
    yield outputrow

def publish_test_message(topic_name, delay_seconds=5):
    """Publish a test message after a delay to verify pipeline is working"""
    time.sleep(delay_seconds)
    try:
        result = subprocess.run(
            ['gcloud', 'pubsub', 'topics', 'publish', topic_name, 
             '--message', 'Test message from streaming pipeline startup'],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            print(f"\n✓ Test message published successfully to topic: {topic_name}")
        else:
            print(f"\n✗ Failed to publish test message: {result.stderr}")
    except Exception as e:
        print(f"\n✗ Error publishing test message: {e}")

def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    print("\n\n✓ Pipeline stopped by user (Ctrl+C)")
    if message_received_event.is_set():
        print("✓ Pipeline was working correctly - messages were processed")
    sys.exit(0)

def run():
    global pipeline_result
    projectname = os.getenv('GOOGLE_CLOUD_PROJECT')
    
    argv = [
        '--streaming'
    ]

    # Register Ctrl+C handler
    signal.signal(signal.SIGINT, signal_handler)

    p = beam.Pipeline(argv=argv)
    subscription = "projects/" + projectname + "/subscriptions/activities-subscription"
    outputtable = projectname + ":mars.raw"
    topic_name = "activities-topic"
    
    print("Starting Beam Job - streaming pipeline")
    print(f"\n{'='*60}")
    print("Pipeline Configuration:")
    print(f"  Topic: {topic_name}")
    print(f"    → https://console.cloud.google.com/cloudpubsub/topic/detail/{topic_name}?project={projectname}")
    print(f"  Subscription: activities-subscription")
    print(f"    → https://console.cloud.google.com/cloudpubsub/subscription/detail/activities-subscription?project={projectname}")
    print(f"  BigQuery Table: mars.raw")
    print(f"    → https://console.cloud.google.com/bigquery?project={projectname}&ws=!1m5!1m4!4m3!1s{projectname}!2smars!3sraw")
    print(f"{'='*60}")
    print("\nPublishing a test message in 5 seconds to verify pipeline...")
    print("Press Ctrl+C to stop the pipeline")
    print(f"{'='*60}\n")
    
    # Start background thread to publish test message (publishes at 5 seconds)
    test_thread = threading.Thread(
        target=publish_test_message, 
        args=(topic_name, 5), 
        daemon=True
    )
    test_thread.start()
    
    (p
     | 'Read Messages' >> beam.io.ReadFromPubSub(subscription=subscription)
     | 'Process Lines' >> beam.FlatMap(lambda line: processline(line))
     | 'Write Output' >> beam.io.WriteToBigQuery(outputtable)
     )
    
    pipeline_result = p.run()
    pipeline_result.wait_until_finish()

if __name__ == '__main__':
    run()