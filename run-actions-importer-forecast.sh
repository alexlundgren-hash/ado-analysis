#!/bin/bash

# run-actions-importer-forecast.sh
#
# Runs a GitHub Actions Importer forecast (via the actions-importer Docker
# image, no local `gh` CLI extension required) across multiple Azure DevOps
# organizations.
#
# Usage:
#   ./run-actions-importer-forecast.sh [-c <csv-file>] [-o <output-dir>] [-s] [-h]
#
# Environment:
#   - .env.local or .env must set GITHUB_ACCESS_TOKEN and GITHUB_INSTANCE_URL
#     (passed through to the container so it can authenticate to GitHub,
#     e.g. to pull a private/patched image and for future migrate steps).
#   - .env.local or .env may set GHACTIONS_IMPORTER_IMAGE (Docker image to
#     use; defaults to ghcr.io/actions-importer/cli).
#   - CSV file (from -c, $ORGS_CSV, or orgs.csv) must have columns:
#     organization, custom_url (optional), personal_access_token
#     - For cloud orgs: azure-devops-instance-url is https://dev.azure.com
#       and azure-devops-organization is the 'organization' column value.
#     - For on-prem/custom rows (custom_url set): azure-devops-organization
#       is derived from the last path segment of custom_url (e.g. the
#       collection name), and azure-devops-instance-url is the remaining
#       base URL. This mirrors how python-script/pipeline_activity_report_v2.py
#       derives organization_name from a custom_url.
#
# Output layout:
#   <output-dir>/<organization>/         Full forecast output for that org.
#   <output-dir>/meta/<org>_audit_summary.md
#   <output-dir>/meta/<org>_workflow_usage.csv
#     After each successful forecast, audit_summary.md and workflow_usage.csv
#     (if present) are copied into a shared 'meta' folder, prefixed with the
#     org name, for easy cross-org review.
#
# Docker permissions:
#   If your user can't talk to the Docker daemon ("permission denied while
#   trying to connect to the Docker daemon socket"), you have two supported
#   options:
#     1. Run just the `docker` commands with elevated privileges by passing
#        -s/--sudo to this script. CSV/env file reads and the output
#        directory stay owned by the invoking user; only the `docker run`
#        calls are prefixed with `sudo`.
#     2. Run the whole script with sudo: `sudo ./run-actions-importer-forecast.sh`.
#        Note this will create the output directory (and its contents) as
#        root, so later non-sudo runs/tools may need `sudo chown` to read them.
#
# Options:
#   -c, --csv-file <path>     Path to organizations CSV file
#                             (default: $ORGS_CSV, then orgs.csv)
#   -o, --output-dir <dir>    Base output directory for forecast results
#                             (default: output-forecast)
#   -s, --sudo                Run `docker` commands with sudo
#   -h, --help                Show this help message

set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
CSV_FILE=""
OUTPUT_DIR="output-forecast"
DEFAULT_IMAGE="ghcr.io/actions-importer/cli"
USE_SUDO=false
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--csv-file)
            CSV_FILE="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -s|--sudo)
            USE_SUDO=true
            shift
            ;;
        -h|--help)
            grep '^# ' "$0" | sed 's/^# //'
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            exit 1
            ;;
    esac
done

# Determine CSV file to use
if [[ -z "$CSV_FILE" ]]; then
    if [[ -n "$ORGS_CSV" ]]; then
        CSV_FILE="$ORGS_CSV"
    else
        CSV_FILE="$BASE_DIR/orgs.csv"
    fi
fi

# Validate CSV file exists
if [[ ! -f "$CSV_FILE" ]]; then
    echo -e "${RED}Error: CSV file not found: $CSV_FILE${NC}" >&2
    if [[ "$EUID" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]] && [[ -z "$ORGS_CSV" ]]; then
        echo -e "${YELLOW}Hint: running the whole script under 'sudo' resets your environment,${NC}" >&2
        echo -e "${YELLOW}so \$ORGS_CSV (and other exported vars) won't be visible here unless you${NC}" >&2
        echo -e "${YELLOW}use 'sudo -E' or pass it explicitly, e.g.:${NC}" >&2
        echo -e "${YELLOW}  sudo ORGS_CSV=\"\$ORGS_CSV\" $0${NC}" >&2
        echo -e "${YELLOW}  sudo -E $0${NC}" >&2
        echo -e "${YELLOW}  $0 -c \"\$ORGS_CSV\" -s   # recommended: use -s/--sudo instead of sudo'ing the whole script${NC}" >&2
    fi
    exit 1
fi

# Load environment from .env.local or .env. GITHUB_ACCESS_TOKEN and
# GITHUB_INSTANCE_URL are required so the container can authenticate to
# GitHub (e.g. to pull the private/patched image and for future migrate
# steps); GHACTIONS_IMPORTER_IMAGE is optional and picks the Docker image.
ENV_FILE=""
if [[ -f "$BASE_DIR/.env.local" ]]; then
    ENV_FILE="$BASE_DIR/.env.local"
elif [[ -f "$BASE_DIR/.env" ]]; then
    ENV_FILE="$BASE_DIR/.env"
fi

if [[ -n "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

IMPORTER_IMAGE="${GHACTIONS_IMPORTER_IMAGE:-$DEFAULT_IMAGE}"

# Validate required GitHub environment variables
if [[ -z "$GITHUB_ACCESS_TOKEN" ]]; then
    echo -e "${RED}Error: GITHUB_ACCESS_TOKEN not set (checked ${ENV_FILE:-environment}).${NC}" >&2
    exit 1
fi

if [[ -z "$GITHUB_INSTANCE_URL" ]]; then
    echo -e "${RED}Error: GITHUB_INSTANCE_URL not set (checked ${ENV_FILE:-environment}).${NC}" >&2
    exit 1
fi

# Validate docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker is required but was not found on PATH.${NC}" >&2
    exit 1
fi

# Build the docker invocation prefix, optionally elevated with sudo via -s/--sudo.
# Only the `docker` commands are elevated (not the whole script), so
# CSV/env file reads and the output directory stay owned by the invoking user
# unless the whole script itself is run under sudo.
DOCKER_CMD="docker"
if [[ "$USE_SUDO" == true ]]; then
    DOCKER_CMD="sudo docker"
fi

# Allocate a pseudo-TTY for the `docker run` forecast calls when stdout is
# actually attached to a terminal, so the actions-importer CLI streams its
# progress output live instead of buffering it (matching how `gh
# actions-importer` runs it internally). Skipped automatically when output
# is redirected/piped or run non-interactively (e.g. cron), where `-t` would
# either be pointless or fail.
DOCKER_TTY_FLAG=""
if [[ -t 1 ]]; then
    DOCKER_TTY_FLAG="-t"
fi

# Detect permission issues talking to the Docker daemon and fail fast with
# clear guidance, rather than letting every per-org forecast fail one by one.
if ! $DOCKER_CMD info &> /dev/null; then
    echo -e "${RED}Error: unable to talk to the Docker daemon.${NC}" >&2
    if [[ "$USE_SUDO" == true ]]; then
        echo -e "${YELLOW}Even with sudo, 'docker info' failed. Is the Docker daemon running?${NC}" >&2
    else
        echo -e "${YELLOW}This is usually a permissions issue. Re-run with -s/--sudo to elevate${NC}" >&2
        echo -e "${YELLOW}only the docker commands, or run this whole script with sudo.${NC}" >&2
    fi
    exit 1
fi

# Create base output directory
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

# Create a 'meta' folder to collect key summary files from every org,
# each prefixed with the org name, for easy cross-org review.
META_DIR="$OUTPUT_DIR/meta"
mkdir -p "$META_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}GitHub Actions Importer Forecast Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo "CSV File: $CSV_FILE"
echo "Base Output Dir: $OUTPUT_DIR"
echo "Docker Image: $IMPORTER_IMAGE"
echo ""

# Track statistics
TOTAL_ORGS=0
SUCCESSFUL_ORGS=0
FAILED_ORGS=0

# Parse CSV and process each organization
# Skip header row (first line)
while IFS=',' read -r org custom_url pat; do
    # Skip empty lines and header row
    if [[ -z "$org" ]] || [[ "$org" == "organization" ]]; then
        continue
    fi

    org=$(echo "$org" | xargs)  # trim whitespace
    custom_url=$(echo "$custom_url" | xargs)
    pat=$(echo "$pat" | xargs)

    # Skip if required fields are empty
    if [[ -z "$org" ]] || [[ -z "$pat" ]]; then
        echo -e "${YELLOW}Skipping row with empty org or PAT${NC}"
        continue
    fi

    TOTAL_ORGS=$((TOTAL_ORGS + 1))

    # Determine Azure DevOps instance URL and organization name.
    # For custom/on-prem URLs, the organization/collection name is the last
    # path segment (matching AzureDevOpsReporter in pipeline_activity_report_v2.py),
    # and the instance URL is everything before it.
    if [[ -n "$custom_url" ]]; then
        custom_url="${custom_url%/}"
        ADO_INSTANCE_URL="${custom_url%/*}"
        ADO_ORGANIZATION="${custom_url##*/}"
    else
        ADO_INSTANCE_URL="https://dev.azure.com"
        ADO_ORGANIZATION="$org"
    fi

    # Create per-org output directory
    ORG_OUTPUT_DIR="$OUTPUT_DIR/$org"
    mkdir -p "$ORG_OUTPUT_DIR"

    echo -e "${BLUE}[${TOTAL_ORGS}] Processing: $org${NC}"
    echo "  Instance URL: $ADO_INSTANCE_URL"
    echo "  Organization: $ADO_ORGANIZATION"
    echo "  Output Dir: $ORG_OUTPUT_DIR"

    # Run the forecast via the actions-importer Docker image directly.
    # The output directory is mounted so results land on the host at
    # $ORG_OUTPUT_DIR. GITHUB_ACCESS_TOKEN and GITHUB_INSTANCE_URL are
    # passed through so the container can authenticate to GitHub.
    # -t allocates a pseudo-TTY (when stdout is a terminal) so the
    # actions-importer CLI streams its progress output live instead of
    # buffering it, matching how `gh actions-importer` runs it internally.
    if $DOCKER_CMD run --rm $DOCKER_TTY_FLAG \
        -v "$ORG_OUTPUT_DIR:/data/output" \
        -e GITHUB_ACCESS_TOKEN="$GITHUB_ACCESS_TOKEN" \
        -e GITHUB_INSTANCE_URL="$GITHUB_INSTANCE_URL" \
        "$IMPORTER_IMAGE" \
        forecast azure-devops \
        --azure-devops-instance-url "$ADO_INSTANCE_URL" \
        --azure-devops-organization "$ADO_ORGANIZATION" \
        --azure-devops-access-token "$pat" \
        --output-dir /data/output; then
        echo -e "${GREEN}✓ Forecast completed for $org${NC}"
        SUCCESSFUL_ORGS=$((SUCCESSFUL_ORGS + 1))

        # Collect key summary files into the shared meta folder, prefixed
        # with the org name, so they're easy to review across all orgs.
        for summary_file in forecast_report.md; do
            if [[ -f "$ORG_OUTPUT_DIR/$summary_file" ]]; then
                cp "$ORG_OUTPUT_DIR/$summary_file" "$META_DIR/${org}_${summary_file}"
                echo "  Collected: meta/${org}_${summary_file}"
            fi
        done
    else
        echo -e "${RED}✗ Forecast failed for $org${NC}"
        FAILED_ORGS=$((FAILED_ORGS + 1))
    fi
    echo ""

done < "$CSV_FILE"

# Print summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Forecast Run Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Total Organizations: $TOTAL_ORGS"
echo -e "Successful: ${GREEN}$SUCCESSFUL_ORGS${NC}"
echo -e "Failed: ${RED}$FAILED_ORGS${NC}"
echo "Meta Dir: $META_DIR"
echo ""

if [[ $FAILED_ORGS -eq 0 ]] && [[ $TOTAL_ORGS -gt 0 ]]; then
    echo -e "${GREEN}All forecasts completed successfully!${NC}"
    exit 0
elif [[ $TOTAL_ORGS -eq 0 ]]; then
    echo -e "${YELLOW}Warning: No organizations found in CSV file${NC}"
    exit 1
else
    echo -e "${YELLOW}Some forecasts failed. Check output above for details.${NC}"
    exit 1
fi
