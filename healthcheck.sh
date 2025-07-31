#!/bin/bash
set -e

# Check if the runner process is running
if pgrep -f "Runner.Listener" > /dev/null; then
  echo "GitHub runner is running."
  exit 0
else
  echo "GitHub runner process is not running!"
  exit 1
fi
