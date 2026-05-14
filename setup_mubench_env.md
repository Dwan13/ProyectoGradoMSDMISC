# muBench Environment Setup Guide

This guide describes how to use the automated script to provision a reproducible environment for muBench experiments (B1-B8, academic rigor).

## Prerequisites
- Linux (recommended)
- Docker & Docker Compose
- Kubernetes (kubectl, cluster access)
- Helm
- Python 3.8+
- pip
- git

## Steps

1. **Clone the repository** (if not already done):
   ```bash
   git clone <your-mubench-repo-url>
   cd muBench
   ```

2. **Run the setup script:**
   ```bash
   bash setup_mubench_env.sh
   ```
   This will:
   - Check/install required tools
   - Create a Python virtual environment and install dependencies
   - Validate Kubernetes cluster access
   - Deploy Prometheus and Grafana (if not present)
   - Deploy all Realistic Services
   - Validate the environment

3. **Run your experiments:**
   - Follow the README and use the provided scripts for campaign execution and post-processing.

## Troubleshooting
- If any step fails, check the error message and ensure all prerequisites are installed.
- For Kubernetes, ensure your cluster is running and `kubectl` is configured.
- For Prometheus/Grafana, the script uses Helm charts (see script for details).

## Reproducibility
- The script ensures all dependencies and services are provisioned as in the validated academic campaign.
- For custom clusters or cloud environments, adapt the script as needed (e.g., storage classes, ingress).

---

For further details, see the main [README.md](README.md) and [Docs/](Docs/) folder.
