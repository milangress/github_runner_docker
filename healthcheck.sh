#!/bin/bash

# Check if the Docker daemon is running
if ! pgrep dockerd > /dev/null; then
  echo "ERROR: Docker daemon is not running!"
  exit 1
fi

# Check if the runner process is running
if pgrep -f "Runner.Listener" > /dev/null; then
  echo "GitHub runner is running."

  # Check if the .runner file exists (indicates successful configuration)
  if [ -f "/home/docker/actions-runner/.runner" ]; then
    echo "Runner is properly configured."
    exit 0
  else
    echo "Warning: Runner process is running but doesn't seem to be configured properly."
    # Still return success because the process is running
    exit 0
  fi
else
  # Check if we're in configuration phase (within first 3 minutes of container start)
  # Docker daemon + runner startup takes longer with Docker-in-Docker
  UPTIME=$(cat /proc/uptime | awk '{print int($1)}')
  if [ $UPTIME -lt 180 ]; then
    echo "Container recently started, allowing time for Docker daemon and runner to initialize..."
    exit 0
  fi

  echo "ERROR: GitHub runner process is not running!"
  exit 1
fi
