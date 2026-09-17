#!/usr/bin/env bash
# Runs ON YOUR LOCAL MACHINE (has internet, same OS/arch as remote).
#
# What it does:
#   1. Adds Docker's official APT repo (if not already present) and
#      downloads docker-ce + all dependencies as .deb files.
#   2. Builds your app image from a local Dockerfile.
#   3. Saves that image to a .tar file.
#   4. Bundles debs + image + the remote install script into one folder.
#   5. scp's the bundle to the remote host.
#   6. ssh's in and runs the remote install script for you.
#
# Requires: docker already installed locally (to build/save the image),
# OR run this script twice - first time it will install docker locally
# via apt so it CAN build the image, if you don't have it yet.
#
# This script expects the Dockerfile to sit in the SAME directory as this
# script (that's the intended repo layout: clone the repo, cd into the
# folder containing these scripts + the Dockerfile, then run this).
#
# Usage (from inside that folder):
#   ./deploy-docker-offline.sh \
#       --remote-user budiman \
#       --remote-host 70.153.149.155 \
#       [--remote-path /home/budiman/docker-offline] \
#       [--dockerfile-dir .] \
#       [--image-name myapp] \
#       [--image-tag latest] \
#       [--ssh-key ~/.ssh/id_ed25519]

set -euo pipefail

# ---------- defaults ----------
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_PATH="~/docker-offline"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE_DIR="$SCRIPT_DIR"
IMAGE_NAME="$(basename "$SCRIPT_DIR")"
IMAGE_TAG="latest"
SSH_KEY=""
LOCAL_BUNDLE="$HOME/docker-offline-bundle"

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote-user) REMOTE_USER="$2"; shift 2 ;;
    --remote-host) REMOTE_HOST="$2"; shift 2 ;;
    --remote-path) REMOTE_PATH="$2"; shift 2 ;;
    --dockerfile-dir) DOCKERFILE_DIR="$2"; shift 2 ;;
    --image-name) IMAGE_NAME="$2"; shift 2 ;;
    --image-tag) IMAGE_TAG="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^#//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$REMOTE_USER" || -z "$REMOTE_HOST" ]]; then
  echo "ERROR: --remote-user and --remote-host are required."
  echo "Run with --help for usage."
  exit 1
fi

SSH_OPTS=()
SCP_OPTS=()
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY")
  SCP_OPTS+=(-i "$SSH_KEY")
fi

echo "=================================================="
echo " Docker Offline Deploy"
echo "   Remote:      ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
echo "   Dockerfile:  ${DOCKERFILE_DIR}"
echo "   Image:       ${IMAGE_NAME}:${IMAGE_TAG}"
echo "=================================================="

rm -rf "$LOCAL_BUNDLE"
mkdir -p "$LOCAL_BUNDLE/debs" "$LOCAL_BUNDLE/image"

# ---------- 1. Ensure local Docker is available (needed to build/save) ----------
if ! command -v docker &>/dev/null; then
  echo "==> Docker not found locally; installing it here first (this machine has internet)"
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER" || true
  echo "!! You may need to log out/in for docker group membership to take effect."
fi

# ---------- 2. Make sure the Docker APT repo is configured (for downloading debs) ----------
if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
  echo "==> Adding Docker APT repo"
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
fi

echo "==> Refreshing package lists"
sudo apt-get update

# ---------- 3. Download Docker .deb packages + all dependencies ----------
echo "==> Cleaning local apt cache so only relevant debs get collected"
sudo apt-get clean

echo "==> Downloading docker-ce and dependencies as .deb files"
sudo apt-get install -y --download-only \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

cp /var/cache/apt/archives/*.deb "$LOCAL_BUNDLE/debs/"
echo "==> Collected $(ls "$LOCAL_BUNDLE/debs" | wc -l) .deb files"

# ---------- 4. Build the image from the local Dockerfile ----------
if [[ ! -f "${DOCKERFILE_DIR}/Dockerfile" ]]; then
  echo "ERROR: No Dockerfile found in ${DOCKERFILE_DIR}"
  echo "       This script expects to sit in the same directory as the"
  echo "       Dockerfile. Either run it from that directory, or pass"
  echo "       --dockerfile-dir pointing to it."
  exit 1
fi

echo "==> Building image ${IMAGE_NAME}:${IMAGE_TAG} from ${DOCKERFILE_DIR}"
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "${DOCKERFILE_DIR}"

# ---------- 5. Save the image to a tarball ----------
IMAGE_TAR="${LOCAL_BUNDLE}/image/${IMAGE_NAME}_${IMAGE_TAG}.tar"
echo "==> Saving image to ${IMAGE_TAR}"
docker save "${IMAGE_NAME}:${IMAGE_TAG}" -o "${IMAGE_TAR}"

# ---------- 6. Copy the remote install script into the bundle ----------
cp "${SCRIPT_DIR}/remote-install.sh" "$LOCAL_BUNDLE/"
chmod +x "$LOCAL_BUNDLE/remote-install.sh"

echo "==> Bundle contents:"
du -sh "$LOCAL_BUNDLE"/*

# ---------- 7. Transfer the bundle to the remote ----------
echo "==> Transferring bundle to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p ${REMOTE_PATH}"
scp "${SCP_OPTS[@]}" -r "$LOCAL_BUNDLE"/* "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"

# ---------- 8. Run the remote install script over SSH ----------
echo "==> Running remote install script"
ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" \
  "chmod +x ${REMOTE_PATH}/remote-install.sh && ${REMOTE_PATH}/remote-install.sh"

echo "=================================================="
echo " Done. Image ${IMAGE_NAME}:${IMAGE_TAG} is loaded on the remote."
echo " SSH in and run it with:"
echo "   ssh ${REMOTE_USER}@${REMOTE_HOST} 'sudo docker run --rm ${IMAGE_NAME}:${IMAGE_TAG}'"
echo "=================================================="