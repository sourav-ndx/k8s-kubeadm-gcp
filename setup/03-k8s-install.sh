#!/bin/bash
# =============================================================================
# 03-k8s-install.sh
# Run on BOTH control plane and worker nodes
# Installs kubeadm, kubelet, kubectl
# Author: Sourav Nandy | github.com/sourav-ndx
# =============================================================================

set -e

K8S_VERSION="1.28"

echo "============================================="
echo " STEP 3: Install kubeadm, kubelet, kubectl"
echo " Version: v${K8S_VERSION}"
echo " Run this on BOTH nodes"
echo "============================================="

# -----------------------------------------------------------------------------
# INSTALL DEPENDENCIES
# apt-transport-https — allows apt to use HTTPS repositories
# ca-certificates    — SSL certificate verification
# curl + gpg         — download and verify the K8s repo signing key
# -----------------------------------------------------------------------------
echo "[1/3] Installing dependencies..."
sudo apt-get update -q
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
echo "Dependencies installed"

# -----------------------------------------------------------------------------
# ADD KUBERNETES APT REPOSITORY
# Why: K8s binaries are not in the default Ubuntu repos.
# We add the official Kubernetes repository and verify packages
# using the GPG signing key — security measure.
# -----------------------------------------------------------------------------
echo "[2/3] Adding Kubernetes apt repository..."
sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -q
echo "Kubernetes repository added"

# -----------------------------------------------------------------------------
# INSTALL AND HOLD K8s BINARIES
# kubelet   — agent running on every node, manages pods
# kubeadm   — bootstrap tool, sets up cluster components
# kubectl   — CLI to interact with the cluster API
#
# apt-mark hold: CRITICAL — prevents accidental auto-upgrade of K8s binaries.
# An accidental kubelet upgrade immediately breaks the node.
# K8s upgrades must be deliberate, one minor version at a time.
# -----------------------------------------------------------------------------
echo "[3/3] Installing kubelet kubeadm kubectl..."
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
echo "Packages held from automatic upgrade"

# Verify installations
echo ""
echo "Installed versions:"
kubeadm version --output=short
kubelet --version
kubectl version --client --output=yaml | grep gitVersion

echo ""
echo "============================================="
echo " K8s binaries ready."
echo " Control plane: run 04-control-plane.sh"
echo " Worker node:   wait for join command"
echo "============================================="
