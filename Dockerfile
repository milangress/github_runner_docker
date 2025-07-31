FROM ubuntu:20.04

ARG RUNNER_VERSION="2.317.0"
ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH

# GitHub uses "x64" instead of "amd64" in their runner filenames
ARG RUNNER_ARCH=${TARGETARCH}
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      echo "Using x64 runner for amd64 architecture"; \
      export RUNNER_ARCH="x64"; \
    fi

# Update and upgrade the system
RUN apt update -y && apt upgrade -y

# Add a user named docker
RUN useradd -m docker

# Install necessary packages including Docker dependencies
RUN apt install -y --no-install-recommends \
    curl build-essential libssl-dev libffi-dev python3 python3-venv python3-dev python3-pip jq \
    pkg-config ssh ca-certificates gnupg lsb-release unzip git

# Configure Docker repository
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package list and install Docker
RUN apt update -y \
    && apt install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    && echo -e '#!/bin/sh\ndocker compose --compatibility "$@"' > /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose

# Add docker user to docker group
RUN usermod -aG docker docker

# Install additional tools following myoung34's comprehensive approach
# Install Git LFS
ARG GIT_LFS_VERSION="3.4.1"
RUN DPKG_ARCH="$(dpkg --print-architecture)" \
    && curl -s "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-${DPKG_ARCH}-v${GIT_LFS_VERSION}.tar.gz" -L -o /tmp/lfs.tar.gz \
    && tar -xzf /tmp/lfs.tar.gz -C /tmp \
    && /tmp/git-lfs-${GIT_LFS_VERSION}/install.sh \
    && rm -rf /tmp/lfs.tar.gz /tmp/git-lfs-${GIT_LFS_VERSION}

# Install GitHub CLI using jq for JSON parsing (following myoung34's approach)
RUN DPKG_ARCH="$(dpkg --print-architecture)" \
    && GH_CLI_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" https://api.github.com/repos/cli/cli/releases/latest | jq -r '.tag_name' | sed 's/^v//g') \
    && GH_CLI_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" https://api.github.com/repos/cli/cli/releases/latest | jq ".assets[] | select(.name == \"gh_${GH_CLI_VERSION}_linux_${DPKG_ARCH}.deb\")" | jq -r '.browser_download_url') \
    && curl -sSLo /tmp/ghcli.deb "${GH_CLI_DOWNLOAD_URL}" \
    && apt-get -y install /tmp/ghcli.deb \
    && rm /tmp/ghcli.deb

# Install yq using jq for JSON parsing (following myoung34's approach)
RUN DPKG_ARCH="$(dpkg --print-architecture)" \
    && YQ_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" https://api.github.com/repos/mikefarah/yq/releases/latest | jq ".assets[] | select(.name == \"yq_linux_${DPKG_ARCH}.tar.gz\")" | jq -r '.browser_download_url') \
    && curl -s "${YQ_DOWNLOAD_URL}" -L -o /tmp/yq.tar.gz \
    && tar -xzf /tmp/yq.tar.gz -C /tmp \
    && mv "/tmp/yq_linux_${DPKG_ARCH}" /usr/local/bin/yq \
    && rm /tmp/yq.tar.gz

# Install AWS CLI with fallback (following myoung34's approach)
RUN (curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" \
    && unzip -q awscliv2.zip -d /tmp/ \
    && /tmp/aws/install \
    && rm awscliv2.zip) \
    || pip3 install --no-cache-dir awscli

# Install container tools (podman, buildah, skopeo) - useful Docker alternatives
RUN apt-get install -y --no-install-recommends podman buildah skopeo || true
# Set up the actions runner
RUN cd /home/docker && mkdir actions-runner && cd actions-runner \
    && curl -o actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz

# Change ownership to docker user and install dependencies
RUN chown -R docker /home/docker && /home/docker/actions-runner/bin/installdependencies.sh

# Copy the start script and health check script and make them executable
COPY start.sh /start.sh
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /start.sh /healthcheck.sh

# Switch to docker user
USER docker

# Define the entrypoint
ENTRYPOINT ["/start.sh"]
