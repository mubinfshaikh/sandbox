#!/bin/bash
for i in $(seq 1 15); do
  curl -fs localhost:3000/health && exit 0
  sleep 2
done
exit 1
