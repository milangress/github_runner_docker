#!/bin/bash

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
  # Check if we're in configuration phase (within first 2 minutes of container start)
  UPTIME=$(cat /proc/uptime | awk '{print int($1)}')
  if [ $UPTIME -lt 120 ]; then
    echo "Container recently started, allowing time for runner to initialize..."
    exit 0
  fi

  echo "ERROR: GitHub runner process is not running!"
  exit 1
fi
