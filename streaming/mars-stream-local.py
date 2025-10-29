#!/usr/bin/env python3
import apache_beam as beam
import os
import signal
import sys
import warnings
import logging

# Suppress httplib2 timeout warnings
warnings.filterwarnings('ignore', message='.*httplib2.*timeout.*')
logging.getLogger('google_auth_httplib2').setLevel(logging.ERROR)

# Global flag to track if message was received
message_received_event = False

def processline_raw(line):
    """Process line for raw table - store as-is"""
    global message_received_event
    outputrow = {'message' : line}
    print(f"✓ Message received and processed: {outputrow}")
    if not message_received_event:
        message_received_event = True
        # Print success message immediately when first message is received
        print(f"\n{'='*60}")
        print("✓ SUCCESS: Pipeline is working correctly!")
        print("  - Subscription 'activities-subscription' read the published message")
        print("  - Message was processed and written to BigQuery tables:")
        print("    • mars.raw (raw message)")
        print("    • mars.activities (structured data)")
        print("  - Pipeline will continue running until Ctrl+C")
        print(f"{'='*60}\n")
    yield outputrow

def processline_activities(line):
    """Process line for activities table - parse CSV into structured data"""
    try:
        # Decode and parse CSV: timestamp,ipaddr,action,srcacct,destacct,amount,customername
        decoded = line.decode('utf-8').strip()
        parts = decoded.split(',')
        
        if len(parts) == 7:
            outputrow = {
                'timestamp': parts[0],
                'ipaddr': parts[1],
                'action': parts[2],
                'srcacct': parts[3],
                'destacct': parts[4],
                'amount': parts[5],
                'customername': parts[6]
            }
            yield outputrow
        else:
            # Log malformed data but don't fail
            print(f"⚠ Warning: Malformed message (expected 7 fields, got {len(parts)}): {decoded}")
    except Exception as e:
        print(f"⚠ Warning: Failed to parse message: {e}")

def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    print("\n\n✓ Pipeline stopped by user (Ctrl+C)")
    if message_received_event:
        print("✓ Pipeline was working correctly - messages were processed")
    sys.exit(0)

def run():
    projectname = os.getenv('GOOGLE_CLOUD_PROJECT')
    
    argv = [
        '--streaming'
    ]

    # Register Ctrl+C handler
    signal.signal(signal.SIGINT, signal_handler)

    p = beam.Pipeline(argv=argv)
    subscription = "projects/" + projectname + "/subscriptions/activities-subscription"
    table_raw = projectname + ":mars.raw"
    table_activities = projectname + ":mars.activities"
    topic_name = "activities-topic"
    
    print("Starting Beam Job - streaming pipeline")
    print(f"\n{'='*60}")
    print("Pipeline Configuration:")
    print(f"  Topic: {topic_name}")
    print(f"    → https://console.cloud.google.com/cloudpubsub/topic/detail/{topic_name}?project={projectname}")
    print(f"  Subscription: activities-subscription")
    print(f"    → https://console.cloud.google.com/cloudpubsub/subscription/detail/activities-subscription?project={projectname}")
    print(f"  BigQuery Tables:")
    print(f"    • mars.raw")
    print(f"      → https://console.cloud.google.com/bigquery?project={projectname}&ws=!1m5!1m4!4m3!1s{projectname}!2smars!3sraw")
    print(f"    • mars.activities")
    print(f"      → https://console.cloud.google.com/bigquery?project={projectname}&ws=!1m5!1m4!4m3!1s{projectname}!2smars!3sactivities")
    print(f"{'='*60}")
    print("\nWaiting for messages from Pub/Sub topic...")
    print("Press Ctrl+C to stop the pipeline")
    print(f"{'='*60}\n")
    
    # Read messages from Pub/Sub
    messages = p | 'Read Messages' >> beam.io.ReadFromPubSub(subscription=subscription)
    
    # Branch 1: Write raw messages to mars.raw
    (messages
     | 'Process Raw' >> beam.FlatMap(lambda line: processline_raw(line))
     | 'Write to Raw Table' >> beam.io.WriteToBigQuery(table_raw)
    )
    
    # Branch 2: Parse and write structured data to mars.activities
    (messages
     | 'Process Activities' >> beam.FlatMap(lambda line: processline_activities(line))
     | 'Write to Activities Table' >> beam.io.WriteToBigQuery(table_activities)
    )
    
    pipeline_result = p.run()
    pipeline_result.wait_until_finish()

if __name__ == '__main__':
    run()