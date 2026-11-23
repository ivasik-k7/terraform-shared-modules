# basic

One pool of unprivileged Docker jobs, four to an instance, on the Amazon
ECS-optimized Amazon Linux 2023 AMI (Docker already installed), with the
module's defaults: an S3 cache bucket it creates, the per-pool alarms to the
topic, and a dashboard.

Made before this apply, outside Terraform: the manager and helper images in
ECR, the runner's `glrt-` token in the SSM parameter named by `token_arn`, and
the SSH private key in Secrets Manager. The sequence is in
[../../docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md).

What fails in it: nothing at plan. At run time it needs the endpoints in
`network_contract`, and port 22 allowed between the two security groups.
