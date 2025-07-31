# GitHub Actions Runner Docker

This repository contains a Dockerfile and Docker Compose configuration for setting up self-hosted GitHub Actions runners.

## Features

- Supports both repository and organization runners
- ARM64 architecture support (configurable for other architectures)
- Automatic cleanup when containers stop
- Customizable runner configuration

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
   
   # Add your GitHub registration token
   REG_TOKEN=your-github-token
   ```

4. Build and start the runner:
   ```
   docker-compose up -d
   ```

## Environment Variables

The project uses environment variables for configuration. There are two ways to set them:

1. Create a `.env` file (recommended)
2. Export them in your shell before running `docker-compose up`

### Available Variables

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `REPO` | GitHub repository in format `owner/repo`. Use this for repository runners. | Yes* | - |
| `ORGANIZATION` | GitHub organization name. Use this for organization runners. | Yes* | - |
| `REG_TOKEN` | GitHub token for runner registration. Get this from your GitHub repository or organization settings. | Yes | - |
| `NAME` | Name for the runner. | No | Container hostname |
| `WORK_DIR` | Directory where the runner will store workflow data. | No | `_work` |
| `LABELS` | Custom labels for the runner (comma-separated). | No | - |
| `RUNNER_GROUP` | Runner group name. | No | `Default` |
| `REPLACE_EXISTING` | Whether to replace runners with the same name. | No | `true` |

*Either `REPO` or `ORGANIZATION` must be specified, but not both.

### Example .env File

```
REPO=username/repository
REG_TOKEN=your_github_token_here
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

## Signal Handling

The runner is configured to gracefully deregister from GitHub when the container stops.
This ensures that you don't have "ghost" runners in your GitHub settings.

## License

MIT