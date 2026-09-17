#!/usr/bin/env bash
# Runs ON THE REMOTE HOST. Installs Docker from the .deb files already
# transferred alongside this script, then loads the app image tarball.
set -euo pipefail

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WORKDIR"

echo "==> Installing Docker packages from local .deb files"
sudo dpkg -i ./debs/*.deb || {
  echo "!! dpkg reported missing dependencies. Since this host is offline,"
  echo "!! 'apt-get install -f' won't work here. Re-check that the debs/"
  echo "!! folder contains every package the source machine downloaded."
  exit 1
}

echo "==> Enabling and starting the Docker service"
sudo systemctl enable --now docker

echo "==> Verifying Docker install"
sudo docker version

IMAGE_TAR="$(ls ./image/*.tar 2>/dev/null | head -n1 || true)"
if [[ -n "${IMAGE_TAR}" ]]; then
  echo "==> Loading image from ${IMAGE_TAR}"
  sudo docker load -i "${IMAGE_TAR}"
  echo "==> Images now available on this host:"
  sudo docker images
else
  echo "!! No image tarball found in ./image/ - skipping docker load."
fi

echo "==> Running the container"

sudo docker run -d --name breakout -p 8080:8080 -e VM_HOSTNAME=$(whoami) "${IMAGE_TAR}"

echo "==> Checking the container logs"

sudo docker logs breakout

echo "==> Done."
