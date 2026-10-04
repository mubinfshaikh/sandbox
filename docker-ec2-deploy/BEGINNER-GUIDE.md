# Beginner guide: Docker app on EC2 with ALB, Auto Scaling, CodeDeploy, ECR and Jenkins

Do the phases **in order**. Use one region for everything: **Asia Pacific (Mumbai) `ap-south-1`**.
Check the region name in the top-right of the AWS console before every phase.

Replace `<ACCOUNT_ID>` with your 12-digit account number (top-right menu).

What you are building:

```
GitHub -> Jenkins (build image) -> ECR (stores image)
                    |
                    +-> S3 (bundle) -> CodeDeploy -> EC2 instances in an Auto Scaling Group
Users -> Load Balancer (ALB) -> the EC2 instances (port 3000)
```

---
## Phase 0 - Before you start
1. Sign in to the AWS console. (You are on root; it works, but ideally make an IAM admin user later.)
2. Top-right region dropdown -> choose **Asia Pacific (Mumbai) ap-south-1**.
3. Billing safety: search **Budgets** -> *Create budget* -> Zero spend / monthly $10 -> add your email.
4. Remember: ALB, EC2 and (if used) NAT gateways cost money. Do the **Cleanup** phase at the end.

## Phase 1 - ECR repository (stores Docker images)
1. Search **ECR** -> *Elastic Container Registry* -> **Create repository**.
2. Visibility: **Private**. Name: `sample-app`. Leave the rest -> **Create**.
3. Copy the URI, e.g. `<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/sample-app`.

## Phase 2 - S3 bucket (stores CodeDeploy bundles)
1. Search **S3** -> **Create bucket**.
2. Name: must be globally unique, e.g. `mubin-codedeploy-bundles-<ACCOUNT_ID>`. Region ap-south-1.
3. Keep "Block all public access" **ON**. **Create bucket**. Note the name.

## Phase 3 - IAM roles (permissions)
Search **IAM** -> **Roles** -> **Create role**. Create these three.

### 3a. `app-ec2-role` (for the app servers)
1. Trusted entity type: **AWS service**. Use case: **EC2** -> Next.
2. Tick these policies (use the search box): 
   `AmazonEC2ContainerRegistryReadOnly`, `AmazonS3ReadOnlyAccess`, `AmazonSSMManagedInstanceCore` -> Next.
3. Role name `app-ec2-role` -> **Create role**.

### 3b. `codedeploy-service-role`
1. AWS service. Use case dropdown: type **CodeDeploy**, choose the plain **CodeDeploy** (not "for ECS/Lambda") -> Next.
2. `AWSCodeDeployRole` is pre-attached -> Next. Name `codedeploy-service-role` -> **Create role**.

### 3c. `jenkins-ec2-role`
1. AWS service -> **EC2** -> Next.
2. Attach `AmazonEC2ContainerRegistryPowerUser` -> Next. Name `jenkins-ec2-role` -> **Create role**.
3. Open the new role -> **Add permissions -> Create inline policy -> JSON** and paste
   (replace the bucket name):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["s3:PutObject","s3:GetObject","s3:ListBucket"],
      "Resource": ["arn:aws:s3:::YOUR-BUCKET","arn:aws:s3:::YOUR-BUCKET/*"] },
    { "Effect": "Allow",
      "Action": ["codedeploy:CreateDeployment","codedeploy:GetDeployment",
                 "codedeploy:GetDeploymentConfig","codedeploy:GetApplicationRevision",
                 "codedeploy:RegisterApplicationRevision","codedeploy:GetApplication",
                 "codedeploy:GetDeploymentGroup"],
      "Resource": "*" }
  ]
}
```
   Name it `jenkins-deploy` -> **Create policy**.

## Phase 4 - Security groups (firewalls)
Search **EC2** -> left menu **Security Groups** -> **Create security group**. Use the **default VPC**.

| Name | Inbound rules |
|------|---------------|
| `alb-sg` | HTTP, port 80, source `0.0.0.0/0` (and HTTPS 443 later) |
| `app-sg` | Custom TCP, port **3000**, source = **alb-sg** (pick it from the list) |
| `jenkins-sg` | Custom TCP port **8080**, source **My IP**; SSH 22 from **My IP** (optional) |

Leave outbound as default (all traffic).

> **Using your own VPC instead of the default one?** (e.g. made with the "VPC and more" wizard)
> Its **private** subnets have no internet route unless you pay for a NAT gateway (~$35/month).
> Without internet the servers can't install Docker/the CodeDeploy agent, and can't reach CodeDeploy, ECR or SSM.
> For this guide put the ALB **and** the Auto Scaling group in the **public** subnets (route `0.0.0.0/0 -> igw-...`).
> Check: VPC -> Route tables -> the subnet's table must have a `0.0.0.0/0` route to an `igw-`.

## Phase 5 - Target group and Load Balancer
### 5a. Target group
1. EC2 -> **Target Groups** -> **Create target group**.
2. Target type **Instances**. Name `sample-app-tg`. Protocol **HTTP**, port **3000**. VPC default.
3. Health checks: path `/health`. -> Next.
4. Do NOT register any targets (the ASG will) -> **Create target group**.
5. Open the target group -> **Attributes** -> **Edit** -> Deregistration delay **30** seconds -> Save.
   *Why:* the default is 300 s, and CodeDeploy waits that long per server on every deployment.

### 5b. Application Load Balancer
1. EC2 -> **Load Balancers** -> **Create load balancer** -> **Application Load Balancer**.
2. Name `sample-app-alb`. Scheme **Internet-facing**. IP type IPv4.
3. Network mapping: default VPC, tick **at least 2 Availability Zones** (2 subnets).
4. Security group: remove default, select **alb-sg**.
5. Listener HTTP:80 -> forward to `sample-app-tg`.
6. **Create load balancer**. Note its **DNS name** (you will open it in the browser later).

## Phase 6 - Launch template (blueprint for the app servers)
1. EC2 -> **Launch Templates** -> **Create launch template**. Name `sample-app-lt`.
2. Tick "Provide guidance... Auto Scaling" if shown.
3. **AMI**: Quick Start -> **Ubuntu** -> choose **Ubuntu Server 24.04 LTS** (64-bit x86).
   This guide is tested on 24.04. 26.04 is very new and the CodeDeploy agent may not support it yet.
4. Instance type: `t3.micro` (or `t2.micro` if free-tier).
5. Key pair: "Don't include" is fine (we can use Session Manager instead of SSH).
6. Network settings: select **app-sg**. If you use your own VPC: **Advanced network configuration** ->
   **Auto-assign public IP: Enable** (the wizard's public subnets don't assign one by themselves).
7. **Advanced details**:
    - IAM instance profile: `app-ec2-role`
    - **User data (required)**: paste the whole of `user-data.sh` from this folder. Check `REGION=ap-south-1` at the top.
      This installs Docker, the AWS CLI and the **CodeDeploy agent**. If you skip it, every deployment fails with
      *"CodeDeploy agent was not able to receive the lifecycle event"*.
8. **Create launch template**.

> Servers need internet access to install Docker and the agent. Default-VPC subnets (and your own VPC's **public** subnets) have it; private subnets don't.

## Phase 7 - Auto Scaling Group
1. EC2 -> **Auto Scaling Groups** -> **Create Auto Scaling group**. Name `sample-app-asg`.
2. Launch template: `sample-app-lt` -> Next.
3. Network: default VPC, select **2+ subnets** in different AZs -> Next.
   Own VPC: pick the **public** subnets only, never the private ones (see the note in Phase 4).
4. Load balancing: **Attach to an existing load balancer** -> **Choose from your load balancer target groups** -> `sample-app-tg`.
5. Health checks: **tick EC2 only for now** (do NOT tick ELB yet). Grace period 300 s.
   *Why:* before the first deployment there's no app on the servers, so the ALB check fails and ASG would keep killing them. Switch to ELB after Phase 10 works.
6. Group size: desired **2**, min **2**, max **4**. Scaling policy: **Target tracking**, CPU 50%.
7. Next -> Next -> **Create Auto Scaling group**.
8. Wait ~3 minutes. EC2 -> Instances: you should see 2 new instances **Running**.
9. Check the agent before the first deploy: select an instance -> **Connect** -> **Session Manager** and run
   `sudo systemctl is-active codedeploy-agent docker` -> both must say `active`.
   If Session Manager can't connect, the server has no internet (wrong subnet) - fix that first.

## Phase 8 - CodeDeploy
### 8a. Application
1. Search **CodeDeploy** -> **Applications** -> **Create application**.
2. Name `sample-app`. Compute platform **EC2/On-premises** -> **Create**.

### 8b. Deployment group
1. Inside the app -> **Create deployment group**. Name `sample-app-dg`.
2. Service role: `codedeploy-service-role`.
3. Deployment type: **In-place**.
4. Environment configuration: tick **Amazon EC2 Auto Scaling groups** -> choose `sample-app-asg`.
5. Agent configuration: "Never" (our user-data installs it) or "Now and schedule updates".
6. Deployment settings: `CodeDeployDefault.OneAtATime` (safest for 2 servers).
7. Load balancer: tick **Enable load balancing** -> Application Load Balancer -> select `sample-app-tg`.
8. **Create deployment group**.

## Phase 9 - Jenkins server
### 9a. Launch the instance
1. EC2 -> **Launch instance**. Name `jenkins`. AMI **Ubuntu 24.04/26.04**. Type **t3.small** or bigger (t3.micro is too small).
2. Security group: select existing **jenkins-sg**. Storage 20 GiB.
3. Advanced details -> IAM instance profile: **jenkins-ec2-role**.
4. **Launch**. Then connect: select the instance -> **Connect** -> *EC2 Instance Connect* (or Session Manager if enabled).

### 9b. Install software (paste in the terminal)
```bash
sudo apt-get update
sudo apt-get install -y docker.io openjdk-21-jre unzip zip git curl fontconfig
sudo systemctl enable --now docker

# AWS CLI v2
curl -s https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip
unzip -q /tmp/a.zip -d /tmp && sudo /tmp/aws/install
aws --version
```
Install Jenkins using the **current official apt instructions** (the signing-key URL changes yearly):
https://www.jenkins.io/doc/book/installing/linux/#debianubuntu - copy the "Long Term Support release" commands.

Then:
```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
sudo systemctl status jenkins     # should say active (running)
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

### 9c. Set up Jenkins in the browser
1. Open `http://<jenkins-public-ip>:8080`. Paste the admin password.
2. **Install suggested plugins**. Create your admin user.
3. Create the job: **New Item** -> name `sample-app` -> **Pipeline** -> OK.
4. Pipeline section: Definition **Pipeline script from SCM** -> SCM **Git**.
   - Repository URL: `https://github.com/mubinfshaikh/sandbox.git`
     (if the repo is private: Add credentials -> *Username with password*, username = GitHub user, password = a GitHub personal access token with `repo` scope).
   - Branch: `*/docker-ec2-asg-loadbalancer`
   - Script Path: `docker-ec2-deploy/Jenkinsfile`
5. **Save**.

### 9d. Edit values in the repo
In `docker-ec2-deploy/Jenkinsfile` set:
`REGION = 'ap-south-1'`, `ACCOUNT = '<ACCOUNT_ID>'`, `BUCKET = '<your bucket>'`.
Commit and push to GitHub.

## Phase 10 - First deployment
1. Jenkins -> `sample-app` -> **Build Now**. Open **Console Output**. Stages: Build -> Push -> Bundle -> Deploy.
2. CodeDeploy console -> Deployments: watch it go to **Succeeded** (it updates one server at a time).
   The **BlockTraffic** step waits for the deregistration delay (30 s after Phase 5a step 5, 5 minutes if you skipped it). This is normal, not stuck.
3. EC2 -> Target Groups -> `sample-app-tg` -> Targets: both **healthy**.
4. Open `http://<ALB-DNS-name>/` in a browser. Refresh a few times; the hostname should switch between the two servers.
5. Now switch the ASG health check to ELB: ASG -> Details -> Health checks -> Edit -> tick **ELB**.
6. Optional: Jenkins -> Configure -> Build Triggers -> **GitHub hook trigger** (add a webhook in the GitHub repo: `http://<jenkins-ip>:8080/github-webhook/`) so each push deploys automatically.

## Troubleshooting
| Problem | What to check |
|---|---|
| Jenkins: `docker: permission denied` | `sudo usermod -aG docker jenkins` then `sudo systemctl restart jenkins` |
| Jenkins: `Unable to locate credentials` | Instance profile `jenkins-ec2-role` not attached (EC2 -> Actions -> Security -> Modify IAM role) |
| ECR push denied | Role missing `AmazonEC2ContainerRegistryPowerUser`, or wrong region/account in Jenkinsfile |
| Deployment fails: *"CodeDeploy agent was not able to receive the lifecycle event"* | The agent isn't running or can't reach AWS. 1) Launch template has no user data (Phase 6 step 7). 2) ASG uses private subnets with no NAT (Phase 4 note). Fix the launch template / ASG subnets, then ASG -> **Instance refresh** to replace the servers |
| EC2 -> Actions -> Monitor -> **Get system log** shows `SSM Agent ... send request failed` | Server has no internet: subnet has no `0.0.0.0/0` route to an internet gateway, or no public IP |
| Jenkins Deploy stage "stuck" ~5 min, ALB shows 503 | Deregistration delay still 300 s (Phase 5a step 5). 503 during a deploy = deployment setting `AllAtOnce`; use `OneAtATime` (Phase 8b step 6) |
| CodeDeploy stuck / "agent not found" | On the server: `sudo systemctl status codedeploy-agent`; log `/var/log/aws/codedeploy-agent/codedeploy-agent.log`; check user-data ran: `/var/log/cloud-init-output.log` |
| Agent won't install on Ubuntu 26.04 | New OS may be unsupported; use Ubuntu 24.04 AMI, or build the agent from the aws-codedeploy-agent GitHub source |
| Script failed in hook | `/opt/codedeploy-agent/deployment-root/<dep-id>/<group-id>/logs/scripts.log` |
| ECR pull denied on server | `app-ec2-role` missing ECR read policy |
| Targets unhealthy | `app-sg` must allow 3000 from `alb-sg`; `curl localhost:3000/health` on the server; `docker ps` |
| ALB URL times out | `alb-sg` must allow 80 from anywhere; ALB in public subnets |

## Cleanup (stop charges)
Delete in this order: Auto Scaling group -> Load balancer -> Target group -> CodeDeploy app -> Jenkins instance -> Launch template -> ECR images/repo -> S3 bucket -> (IAM roles and security groups are free).
