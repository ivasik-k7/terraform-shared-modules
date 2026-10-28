# basic

The smallest call: `app-assets-<account>-<region>`, versioned, SSE-S3,
private, TLS-only, old versions expiring after 90 days. The customer key and
access logging checks are acknowledged on purpose. Attach
`output.read_policy_json` to the roles that read it.
