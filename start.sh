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
GITHUB_TOKEN=${GITHUB_TOKEN:-""}
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
echo "REG_TOKEN:        $(if [[ -n "$REG_TOKEN" ]]; then echo "Provided"; else echo "Will be auto-generated"; fi)"
echo "GITHUB_TOKEN:     $(if [[ -n "$GITHUB_TOKEN" ]]; then echo "Provided"; else echo "Not provided"; fi)"
echo "======================================"

cd /home/docker/actions-runner

# Function to generate registration token via GitHub API
generate_registration_token() {
    local api_url
    local response
    local token
    local expires_at

    if [[ -n "$ORGANIZATION" ]]; then
        api_url="https://api.github.com/orgs/${ORGANIZATION}/actions/runners/registration-token"
        echo "Generating registration token for organization: ${ORGANIZATION}"
    elif [[ -n "$REPO" ]]; then
        api_url="https://api.github.com/repos/${REPO}/actions/runners/registration-token"
        echo "Generating registration token for repository: ${REPO}"
    else
        echo "Error: Either ORGANIZATION or REPO must be specified"
        exit 1
    fi

    echo "Calling GitHub API to generate registration token..."
    response=$(curl -s -L \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${api_url}")

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to call GitHub API"
        exit 1
    fi

    # Check if the response contains an error
    if echo "$response" | grep -q '"message"'; then
        echo "Error from GitHub API:"
        echo "$response"
        exit 1
    fi

    # Extract token from response
    token=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    expires_at=$(echo "$response" | grep -o '"expires_at":"[^"]*"' | cut -d'"' -f4)

    if [[ -z "$token" ]]; then
        echo "Error: Could not extract token from API response"
        echo "Response: $response"
        exit 1
    fi

    echo "Registration token generated successfully!"
    echo "Token expires at: ${expires_at}"

    REG_TOKEN="$token"
}

# Check if we need to generate a registration token
if [[ -z "$REG_TOKEN" ]]; then
    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo "Error: Either REG_TOKEN or GITHUB_TOKEN must be provided"
        echo ""
        echo "Options:"
        echo "1. Provide REG_TOKEN directly (manual token from GitHub)"
        echo "2. Provide GITHUB_TOKEN (Personal Access Token with admin:org scope) to auto-generate REG_TOKEN"
        exit 1
    fi

    generate_registration_token
else
    echo "Using provided REG_TOKEN"
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
