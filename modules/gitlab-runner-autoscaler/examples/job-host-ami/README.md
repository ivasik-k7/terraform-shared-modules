# job-host-ami

The job instance AMI, built by `modules/ami-builder` from
[../../images/job-host/gitlab-runner-job-host.yaml](../../images/job-host/gitlab-runner-job-host.yaml):
Docker for `ec2-user`, the ECS agent off, container logs bounded, the helper
image pre-pulled, and a Docker Hub mirror.

It is a workspace of its own because `modules/ami-builder` supports
hashicorp/aws 5.x and the runner module 6.x. Run the pipeline once
(`aws imagebuilder start-image-pipeline-execution --image-pipeline-arn <pipeline_arn>`),
read the AMI id from the SSM parameter it publishes, and pin it as the runner's
`ami_id`.

The build instance may pull the helper repository and nothing else
(`aws_iam_policy.pull_helper`). The build subnet needs the ECR and S3
endpoints, and the Amazon Linux package repositories if the parent AMI has no
Docker.

What fails in it: nothing at plan. The component's use of the AWS CLI and
`dnf` in an isolated subnet is unverified ([../../docs/RESEARCH.md](../../docs/RESEARCH.md), 4.9, 4.10).
