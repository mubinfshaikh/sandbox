#!/bin/bash
set -e
source "$(dirname "$0")/../image.env"
docker rm -f app 2>/dev/null || true
docker run -d --name app --restart unless-stopped -p 3000:3000 \
  -e APP_VERSION="${IMAGE##*:}" "$IMAGE"
