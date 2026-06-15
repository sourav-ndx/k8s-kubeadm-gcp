#!/bin/bash
# =============================================================================
# 02-containerd.sh
# Run on BOTH control plane and worker nodes
# Installs and configures containerd as the container runtime
# Author: Sourav Nandy | github.com/sourav-ndx
# =============================================================================

set -e

echo "============================================="
echo " STEP 2: Install and Configure containerd"
echo " Run this on BOTH nodes"
echo "============================================="

# -----------------------------------------------------------------------------
# INSTALL CONTAINERD
# Why containerd and not Docker:
# Kubernetes removed Docker as a supported runtime in v1.24.
# containerd is what Docker itself uses underneath — it is the industry
# standard CRI (Container Runtime Interface) for Kubernetes.
# -----------------------------------------------------------------------------
echo "[1/3] Installing containerd..."
sudo apt-get update -q
sudo apt-get install -y containerd
echo "containerd installed"

# -----------------------------------------------------------------------------
# GENERATE DEFAULT CONFIG
# Why: Without this file, containerd runs with built-in defaults
# that are incompatible with Kubernetes cgroup management.
# -----------------------------------------------------------------------------
echo "[2/3] Generating containerd config..."
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
echo "Default config generated at /etc/containerd/config.toml"

# -----------------------------------------------------------------------------
# SET SystemdCgroup = true
# Why: THIS IS CRITICAL. Kubernetes uses systemd to manage cgroups
# (container resource limits — CPU, memory). containerd must use the
# SAME cgroup driver. A mismatch causes kubelet to crash on startup.
# This single line is the most common kubeadm failure cause.
# -----------------------------------------------------------------------------
echo "[3/3] Setting SystemdCgroup = true..."
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Verify the change
grep "SystemdCgroup" /etc/containerd/config.toml

# Restart and enable containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Verify containerd is running
echo ""
echo "containerd status:"
sudo systemctl status containerd --no-pager | grep -E "Active|Loaded"

echo ""
echo "============================================="
echo " containerd ready. Proceed to 03-k8s-install.sh"
echo "============================================="
