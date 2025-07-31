# GitHub Actions Runner Docker

This repository contains a Dockerfile and Docker Compose configuration for setting up self-hosted GitHub Actions runners.

## Features

- Supports both repository and organization runners
- **Automatic token generation** via GitHub API (no manual token creation needed)
- **True Docker-in-Docker isolation** - complete isolated Docker daemon with buildx support
- ARM64 architecture support (configurable for other architectures)
- Automatic cleanup when containers stop
- Customizable runner configuration
- Comprehensive tooling for modern CI/CD workflows

## Quick Start

1. Clone this repository:
   ```
   git clone https://github.com/yourusername/github_runner_docker.git
   cd github_runner_docker
   ```

2. Create a `.env` file from the example:
   ```
   cp .env.example .env
   ```

3. Edit the `.env` file with your specific configuration:
   ```
   # Set either REPO or ORGANIZATION (not both)
   REPO=your-username/your-repo

   # Option 1: Use GitHub Personal Access Token (recommended - auto-generates registration token)
   GITHUB_TOKEN=ghp_your_personal_access_token_here

   # Option 2: Manual registration token (alternative)
   # REG_TOKEN=your-manual-registration-token
   ```

4. Build and start the runner:
   ```bash
   docker-compose up -d
   ```

## Environment Variables

The project uses environment variables for configuration. There are two ways to set them:

1. Create a `.env` file (recommended)
2. Export them in your shell before running `docker-compose up`

### Available Variables

| Variable           | Description                                                                                                                                                  | Required | Default            |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ------------------ |
| `REPO`             | GitHub repository in format `owner/repo`. Use this for repository runners.                                                                                   | Yes*     | -                  |
| `ORGANIZATION`     | GitHub organization name. Use this for organization runners.                                                                                                 | Yes*     | -                  |
| `GITHUB_TOKEN`     | Personal Access Token with `admin:org` scope (for orgs) or `repo` scope (for repos). **Recommended approach** - automatically generates registration tokens. | Yes**    | -                  |
| `REG_TOKEN`        | Manual GitHub registration token. Alternative to `GITHUB_TOKEN`. Get this from your GitHub repository or organization settings.                              | Yes**    | -                  |
| `NAME`             | Name for the runner.                                                                                                                                         | No       | Container hostname |
| `WORK_DIR`         | Directory where the runner will store workflow data.                                                                                                         | No       | `_work`            |
| `LABELS`           | Custom labels for the runner (comma-separated).                                                                                                              | No       | -                  |
| `RUNNER_GROUP`     | Runner group name.                                                                                                                                           | No       | `Default`          |
| `REPLACE_EXISTING` | Whether to replace runners with the same name.                                                                                                               | No       | `true`             |

*Either `REPO` or `ORGANIZATION` must be specified, but not both.
**Either `GITHUB_TOKEN` or `REG_TOKEN` must be provided.

## Creating GitHub Tokens

### Option 1: Personal Access Token (Recommended)

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Select appropriate scopes:
   - For **organization runners**: `admin:org` scope
   - For **repository runners**: `repo` scope
4. Copy the generated token and use it as `GITHUB_TOKEN`

### Option 2: Fine-grained Personal Access Token

1. Go to GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Click "Generate new token"
3. Select appropriate permissions:
   - For **organization runners**: "Self-hosted runners" organization permissions (write)
   - For **repository runners**: "Actions" repository permissions (write)
4. Copy the generated token and use it as `GITHUB_TOKEN`

### Option 3: Manual Registration Token (Alternative)

1. Go to your repository/organization settings
2. Navigate to Actions → Runners
3. Click "New self-hosted runner"
4. Copy the token from the configuration command
5. Use it as `REG_TOKEN` (expires in 1 hour)

### Example .env Files

**Using Personal Access Token (Recommended):**
```
ORGANIZATION=my-org
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
LABELS=self-hosted,linux,docker
```

**Using Manual Registration Token:**
```
REPO=username/repository
REG_TOKEN=AABBCCDDEE1234567890
LABELS=self-hosted,linux
```

## Runner Groups and Labels

Runner groups can be used to limit which repositories can use the runners in an organization.
Labels can be used to target specific runners in your workflow files:

```yaml
jobs:
  build:
    runs-on: self-hosted # Or your custom label
```

## Multi-Architecture Support

This Docker setup supports multiple architectures out of the box. The Dockerfile is configured to handle both ARM64 and x64 architectures automatically during the build process.

When building with Docker Buildx, the system will:
1. Automatically detect the target architecture
2. Download the appropriate GitHub runner version
3. Handle the naming difference between Docker's architecture naming ('amd64') and GitHub's runner naming ('x64')

No configuration is needed for architecture - the system handles this automatically.

To build for a specific architecture using Docker Buildx:
```
docker buildx build --platform linux/amd64 -t github-runner:amd64 .
docker buildx build --platform linux/arm64 -t github-runner:arm64 .
```

## Docker-in-Docker Support

This runner includes **full Docker-in-Docker isolation** with its own Docker daemon running inside the container.

### **Features:**
- ✅ **Completely isolated** - runs its own Docker daemon (no host Docker access)
- ✅ **Perfect for `docker buildx`** - built-in buildx support with experimental features
- ✅ **Production-ready** - eliminates permission issues and provides complete isolation
- ✅ **Multi-platform builds** - supports ARM64 and x64 architectures
- ✅ **Full Docker functionality** - build, push, compose, everything works

### **What This Enables:**
- Building and pushing Docker images
- Running containerized tests
- Using Docker Compose
- Docker buildx multi-platform builds
- Complex CI/CD pipelines
- Any workflow requiring Docker commands

### **Usage:**
```bash
docker-compose up -d
```

The runner automatically starts its own Docker daemon with optimized settings for CI/CD workloads. No manual configuration needed!

### **Security Model:**
- Container starts as **root** (required for Docker daemon)
- Docker daemon runs as **root** (standard Docker requirement)
- GitHub Actions runner runs as **docker user** (security best practice)
- Docker socket permissions allow docker user to access Docker daemon

## Included Build Dependencies & Tools

This runner image includes comprehensive tooling for modern CI/CD workflows:

### **Core Build Tools:**
- build-essential
- libssl-dev, pkg-config, openssl, libffi-dev
- python3 and pip
- git and **Git LFS** (for large file handling)

### **Container & Cloud Tools:**
- **Docker CE, Docker CLI, and Docker Compose** (full Docker support)
- **Podman, Buildah, Skopeo** (alternative container tools)
- **AWS CLI** (for cloud deployments)

### **Development & CI/CD Tools:**
- **GitHub CLI** (`gh`) - for GitHub API interactions
- **yq** - YAML processor for configuration files
- **jq** - JSON processor (used throughout scripts)
- **ssh** - for secure connections

### **Architecture Support:**
- Full ARM64 and x64 architecture support
- Multi-platform Docker builds

These dependencies support a wide range of workflows including Rust/OpenSSL projects, containerized applications, cloud deployments, and complex CI/CD pipelines.

## Health Check

The Docker setup includes a built-in health check that monitors the status of the GitHub runner. This helps Docker determine if the container is functioning properly and enables automatic recovery if the runner crashes.
Verifies that the runner process (`Runner.Listener`) is actually running

## Signal Handling

The runner is configured to gracefully deregister from GitHub when the container stops.
This ensures that you don't have "ghost" runners in your GitHub settings.

## License

MIT