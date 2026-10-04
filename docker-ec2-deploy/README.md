# Docker app on EC2 (ASG + ALB) via Jenkins, ECR and CodeDeploy

Flow: GitHub → Jenkins (build/push) → ECR → CodeDeploy → ASG instances (Ubuntu) behind an ALB.

Files: `app/` + `Dockerfile` (sample app), `Jenkinsfile`, `appspec.yml` + `scripts/` (CodeDeploy hooks), `user-data.sh` (launch template).

## Setup order
1. ECR repo `sample-app`; S3 bucket for bundles.
2. IAM: EC2 role (ECR read, S3 read, SSM core); CodeDeploy service role (`AWSCodeDeployRole`); Jenkins role (ECR push, S3 write, `codedeploy:*Deployment*`, `RegisterApplicationRevision`).
3. SGs: `alb-sg` (80/443 from anywhere), `app-sg` (3000 from `alb-sg`).
4. Target group (HTTP 3000, health `/health`, deregistration delay 30 s) + internet-facing ALB listener 80 → TG.
5. Launch template (Ubuntu AMI, `user-data.sh`, EC2 role, `app-sg`) + ASG (min 2, 2+ AZs, **public subnets or private+NAT** - the agent needs internet, attach TG, ELB health checks, CPU target tracking). User data is required: it installs the CodeDeploy agent.
6. CodeDeploy app `sample-app`, deployment group `sample-app-dg`: in-place, target the ASG, load balancer enabled with the TG, OneAtATime/HalfAtATime, rollback on failure.
7. Jenkins on its own EC2 (Java, Jenkins, docker, AWS CLI, zip; `jenkins` in `docker` group). Pipeline job with script path `docker-ec2-deploy/Jenkinsfile`, GitHub webhook.
8. Edit `ACCOUNT`/`REGION` in `Jenkinsfile`, `REGION` in `user-data.sh`.

Verify: `curl http://<ALB-DNS>/` repeatedly; hostname should alternate.

Note: tested on Ubuntu 24.04. 26.04 is new; confirm the CodeDeploy agent supports it before switching.
