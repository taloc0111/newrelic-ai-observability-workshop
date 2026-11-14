#!/usr/bin/env bash
# Install Docker Engine (docker-ce, NOT Docker Desktop) + kind, kubectl, helm, k9s inside WSL2 Ubuntu.
# Idempotent: checks first, installs only what is missing. Run: bash setup-tools.sh
set -euo pipefail

echo "== current state =="; which docker kind kubectl helm k9s || true
docker info --format "docker server {{.ServerVersion}}" 2>/dev/null || echo "docker: not running / not installed"

# ---- A. Docker Engine ----
if ! command -v docker >/dev/null; then
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
  sudo usermod -aG docker "$USER"
  echo ">> docker installed. CLOSE and REOPEN the WSL shell so the docker group applies."
fi
sudo systemctl enable --now docker 2>/dev/null || sudo service docker start || true

# ---- B. kind / kubectl / helm / k9s ----
# kind: GitHub "latest" release = latest STABLE (the kind.sigs.k8s.io /dl/latest URL serves alpha builds)
[ -e /usr/local/bin/kind ] || {
  curl -Lo ./kind https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-linux-amd64
  chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind; }
[ -e /usr/local/bin/kubectl ] || {
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x ./kubectl && sudo mv ./kubectl /usr/local/bin/kubectl; }
[ -e /usr/local/bin/helm ] || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
[ -e /usr/local/bin/k9s ] || {
  curl -Lo ./k9s.tgz https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz
  tar -xzf k9s.tgz k9s && sudo mv k9s /usr/local/bin/ && rm k9s.tgz; }

echo "== verify =="
kind version && kubectl version --client && helm version --short && k9s version --short
