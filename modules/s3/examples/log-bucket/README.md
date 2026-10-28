# log-bucket

The account's server access log bucket. Each source bucket in the same
account and region points `access_logging.target_bucket` here. It uses SSE-S3
because S3 cannot deliver access logs to an SSE-KMS bucket, has no Object
Lock, and logs nowhere itself; the plan refuses the first two. Logs move to
Glacier Instant Retrieval after 90 days and expire after a year.
