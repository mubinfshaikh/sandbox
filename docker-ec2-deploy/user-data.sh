#!/bin/bash
# EC2 launch template user data (Ubuntu). Set REGION before use.
set -e
REGION=us-east-1
apt-get update
apt-get install -y docker.io ruby-full wget unzip curl
systemctl enable --now docker
usermod -aG docker ubuntu

curl -s https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip
unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install

cd /tmp
wget https://aws-codedeploy-$REGION.s3.$REGION.amazonaws.com/latest/install
chmod +x install && ./install auto
systemctl enable --now codedeploy-agent
