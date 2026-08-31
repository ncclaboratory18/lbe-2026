#!/usr/bin/env bash
# install-docker.sh
# Cleans up Docker Desktop leftovers and installs Docker Engine (CE) on Ubuntu.
# Tested for Ubuntu 24.04 (noble) but should work on other recent Ubuntu releases.

set -euo pipefail

echo "==> Removing any Docker Desktop leftovers..."
sudo apt purge -y docker-desktop 2>/dev/null || true
sudo rm -rf /opt/docker-desktop "$HOME/.docker/desktop" /usr/local/bin/com.docker.cli
sudo rm -f /usr/share/applications/docker-desktop.desktop

echo "==> Updating package index..."
sudo apt update

echo "==> Installing prerequisites..."
sudo apt install -y ca-certificates curl gnupg

echo "==> Adding Docker's official GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
fi

echo "==> Adding Docker's apt repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "==> Updating package index with Docker repo..."
sudo apt update

echo "==> Installing Docker Engine, CLI, containerd, buildx, and compose plugin..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Enabling and starting Docker service..."
sudo systemctl enable docker
sudo systemctl start docker

echo "==> Verifying installation..."
sudo docker run hello-world

echo "==> Adding current user ($USER) to the docker group (run without sudo)..."
sudo usermod -aG docker "$USER"

echo ""
echo "Docker installation complete."
echo "Log out and back in (or run 'newgrp docker') for group changes to take effect."
