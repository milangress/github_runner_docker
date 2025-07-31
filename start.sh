#!/bin/bash

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

./config.sh ${CONFIGURE_OPTS}

# Define cleanup function to remove the runner when the container stops
cleanup() {
    echo "Removing runner..."
    ./config.sh remove --unattended --token ${REG_TOKEN}
}

# Set up traps to ensure the runner is removed when the container is stopped
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Start the runner and wait for it to complete
./run.sh & wait $!
