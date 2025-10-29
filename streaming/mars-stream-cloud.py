#!/usr/bin/env python3
import apache_beam as beam
import os
import datetime

def processline_raw(line):
    """Process line for raw table - store as-is"""
    outputrow = {'message' : line}
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
            # Log malformed data but don't fail the pipeline
            import logging
            logging.warning(f"Malformed message (expected 7 fields, got {len(parts)}): {decoded}")
    except Exception as e:
        import logging
        logging.warning(f"Failed to parse message: {e}")


def run():
    projectname = os.getenv('GOOGLE_CLOUD_PROJECT')
    bucketname = os.getenv('GOOGLE_CLOUD_PROJECT') + '-bucket'
    jobname = 'mars-job-streaming' + datetime.datetime.now().strftime("%Y%m%d%H%M")
    region = 'us-central1'

    # https://cloud.google.com/dataflow/docs/reference/pipeline-options
    argv = [
      '--streaming',
      '--runner=DataflowRunner',
      '--project=' + projectname,
      '--job_name=' + jobname,
      '--region=' + region,
      '--staging_location=gs://' + bucketname + '/staging/',
      '--temp_location=gs://' + bucketname + '/temploc/',
      '--max_num_workers=2',
      '--machine_type=e2-standard-2',
    #   '--service_account_email=marssa@' + projectname + ".iam.gserviceaccount.com"
      '--save_main_session'
    ]

    p = beam.Pipeline(argv=argv)
    subscription = "projects/" + projectname + "/subscriptions/activities-subscription"
    table_raw = projectname + ":mars.raw"
    table_activities = projectname + ":mars.activities"
    
    print("Starting Dataflow Streaming Job")
    print(f"Project: {projectname}")
    print(f"Job Name: {jobname}")
    print(f"Subscription: activities-subscription")
    print(f"Writing to tables: mars.raw, mars.activities")
    print(f"Monitor job at: https://console.cloud.google.com/dataflow/jobs/{region}/{jobname}?project={projectname}")
    
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
    
    result = p.run()
    
    print("")
    print("=" * 60)
    print("✓ Dataflow job submitted successfully!")
    print(f"  Job Name: {jobname}")
    print(f"  Region: {region}")
    print("")
    print("Monitor your Dataflow job:")
    print(f"  https://console.cloud.google.com/dataflow/jobs/{region}/{jobname}?project={projectname}")
    print("")
    print("View BigQuery tables:")
    print(f"  mars.raw: https://console.cloud.google.com/bigquery?project={projectname}&ws=!1m5!1m4!4m3!1s{projectname}!2smars!3sraw")
    print(f"  mars.activities: https://console.cloud.google.com/bigquery?project={projectname}&ws=!1m5!1m4!4m3!1s{projectname}!2smars!3sactivities")
    print("=" * 60)
    print("")


if __name__ == '__main__':
    run()