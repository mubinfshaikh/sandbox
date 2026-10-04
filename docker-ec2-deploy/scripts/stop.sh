#!/bin/bash
docker stop app 2>/dev/null || true
docker rm app 2>/dev/null || true
exit 0
