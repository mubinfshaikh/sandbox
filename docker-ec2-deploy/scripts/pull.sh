#!/bin/bash
set -e
# image.env ("IMAGE=<ecr-uri>:<tag>") sits at the root of the deployment archive
source "$(dirname "$0")/../image.env"
REGISTRY="${IMAGE%%/*}"
REGION=$(echo "$REGISTRY" | cut -d. -f4)
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
docker pull "$IMAGE"
