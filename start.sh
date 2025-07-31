#!/bin/bash
set -e

# Constants for error handling
MAX_RETRIES=5
RETRY_DELAY=30
RETRY_COUNT=0

# Set default values for environment variables
ORGANIZATION=${ORGANIZATION:-""}
REPO=${REPO:-""}
NAME=${NAME:-$(hostname)}
WORK_DIR=${WORK_DIR:-"_work"}
LABELS=${LABELS:-""}
REG_TOKEN=${REG_TOKEN:-""}
RUNNER_GROUP=${RUNNER_GROUP:-"Default"}
REPLACE_EXISTING=${REPLACE_EXISTING:-"true"}

# Log the configuration
echo "===== GitHub Runner Configuration ====="
echo "Organization:     ${ORGANIZATION}"
echo "Repository:       ${REPO}"
echo "Runner Name:      ${NAME}"
echo "Work Directory:   ${WORK_DIR}"
echo "Labels:           ${LABELS}"
echo "Runner Group:     ${RUNNER_GROUP}"
echo "Replace Existing: ${REPLACE_EXISTING}"
echo "======================================"

cd /home/docker/actions-runner

if [[ -z "$REG_TOKEN" ]]; then
    echo "Error: REG_TOKEN is required"
    exit 1
fi

if [[ -n "$ORGANIZATION" ]]; then
    echo "Configuring organization runner for ${ORGANIZATION}"
    RUNNER_URL="https://github.com/${ORGANIZATION}"
elif [[ -n "$REPO" ]]; then
    echo "Configuring repository runner for ${REPO}"
    RUNNER_URL="https://github.com/${REPO}"
else
    echo "Error: Either ORGANIZATION or REPO must be specified"
    exit 1
fi

# Configure the runner
CONFIGURE_OPTS="--url ${RUNNER_URL} --token ${REG_TOKEN} --name ${NAME} --work ${WORK_DIR} --runnergroup ${RUNNER_GROUP}"

if [[ -n "$LABELS" ]]; then
    CONFIGURE_OPTS="${CONFIGURE_OPTS} --labels ${LABELS}"
fi

if [[ "$REPLACE_EXISTING" == "true" ]]; then
    CONFIGURE_OPTS="${CONFIGURE_OPTS} --replace"
fi

# Try to configure the runner with retries
while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    echo "Attempting to configure runner (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)..."

    if ./config.sh ${CONFIGURE_OPTS}; then
        echo "Runner configuration successful!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))

        if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
            echo "Runner configuration failed. Retrying in ${RETRY_DELAY} seconds..."
            sleep $RETRY_DELAY
        else
            echo "ERROR: Failed to configure runner after ${MAX_RETRIES} attempts."
            echo "Please check your REG_TOKEN, repository/organization name, and GitHub access."
            echo "Waiting 300 seconds before exiting to prevent rapid restart loops..."
            sleep 300
            exit 1
        fi
    fi
done

# Define cleanup function to remove the runner when the container stops
cleanup() {
    echo "Removing runner..."
    if ! ./config.sh remove --unattended --token ${REG_TOKEN}; then
        echo "Warning: Failed to remove runner. It may need to be removed manually from GitHub."
    else
        echo "Runner removed successfully."
    fi
}

# Error handling function for runner process
handle_runner_error() {
    echo "ERROR: Runner process exited unexpectedly with status $1"
    echo "Waiting 60 seconds before exiting to prevent rapid restart loops..."
    sleep 60
    exit 1
}

# Set up traps to ensure the runner is removed when the container is stopped
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Start the runner with error handling
echo "Starting GitHub runner..."
./run.sh &
RUNNER_PID=$!

# Wait for runner process and capture exit status
wait $RUNNER_PID
EXIT_STATUS=$?

# If the runner didn't exit cleanly (exit code 0), handle the error
if [ $EXIT_STATUS -ne 0 ]; then
    handle_runner_error $EXIT_STATUS
fi

echo "Runner exited normally."
