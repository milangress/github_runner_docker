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

# Start Docker daemon as root (required for dockerd)
echo "Starting Docker daemon for full Docker-in-Docker isolation..."

# Start dockerd in background with proper settings for DinD
dockerd \
    --host=unix:///var/run/docker.sock \
    --host=tcp://0.0.0.0:2376 \
    --storage-driver=overlay2 \
    --userland-proxy=false \
    --experimental \
    --metrics-addr=0.0.0.0:9323 &

# Wait for Docker daemon to be ready
timeout=60
echo "Waiting for Docker daemon to start..."
while [ $timeout -gt 0 ]; do
    if docker info >/dev/null 2>&1; then
        echo "Docker daemon is ready!"
        echo "Docker version: $(docker --version)"
        echo "Docker buildx version: $(docker buildx version)"
        break
    fi
    echo "Docker daemon starting... ($timeout seconds remaining)"
    sleep 2
    timeout=$((timeout-2))
done

if [ $timeout -le 0 ]; then
    echo "ERROR: Docker daemon failed to start within 60 seconds"
    echo "Checking Docker daemon logs..."
    tail -20 /var/log/docker.log 2>/dev/null || echo "No Docker logs found"
    exit 1
fi

# Ensure buildx is available and create default builder
docker buildx install
docker buildx create --use --name container --driver docker-container || true
echo "Docker buildx builder created successfully"

# Set proper permissions for docker user to access Docker socket
chown docker:docker /var/run/docker.sock
usermod -aG docker docker

# Switch to docker user for GitHub Actions runner (security best practice)
echo "Switching to docker user for GitHub Actions runner..."
cd /home/docker/actions-runner
chown -R docker:docker /home/docker/actions-runner

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

    # Check if the response contains an error using jq
    error_message=$(echo "$response" | jq -r '.message // empty')
    if [[ -n "$error_message" ]]; then
        echo "Error from GitHub API: $error_message"
        echo "Full response: $response"
        exit 1
    fi

    # Extract token from response using jq for reliable JSON parsing
    token=$(echo "$response" | jq -r '.token // empty')
    expires_at=$(echo "$response" | jq -r '.expires_at // empty')

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

# Try to configure the runner with retries (as docker user)
while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    echo "Attempting to configure runner (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)..."

    if su - docker -c "cd /home/docker/actions-runner && ./config.sh ${CONFIGURE_OPTS}"; then
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
    echo "Shutting down GitHub runner..."

    # Remove runner from GitHub (as docker user)
    if ! su - docker -c "cd /home/docker/actions-runner && ./config.sh remove --unattended --token ${REG_TOKEN}"; then
        echo "Warning: Failed to remove runner. It may need to be removed manually from GitHub."
    else
        echo "Runner removed successfully."
    fi

    # Shut down our Docker daemon gracefully
    echo "Shutting down Docker daemon..."
    pkill dockerd || true
    sleep 2
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

# Start the runner with error handling (as docker user)
echo "Starting GitHub runner..."
su - docker -c "cd /home/docker/actions-runner && ./run.sh" &
RUNNER_PID=$!

# Wait for runner process and capture exit status
wait $RUNNER_PID
EXIT_STATUS=$?

# If the runner didn't exit cleanly (exit code 0), handle the error
if [ $EXIT_STATUS -ne 0 ]; then
    handle_runner_error $EXIT_STATUS
fi

echo "Runner exited normally."
