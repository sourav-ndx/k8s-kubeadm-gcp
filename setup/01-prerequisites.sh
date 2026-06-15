#!/bin/bash
# =============================================================================
# 01-prerequisites.sh
# Run on BOTH control plane and worker nodes
# Prepares the Linux OS for Kubernetes installation
# Author: Sourav Nandy | github.com/sourav-ndx
# =============================================================================

set -e  # Exit immediately if any command fails

echo "============================================="
echo " STEP 1: Kubernetes Node Prerequisites"
echo " Run this on BOTH nodes"
echo "============================================="

# -----------------------------------------------------------------------------
# DISABLE SWAP
# Why: Kubernetes scheduler manages memory assuming RAM is the only memory tier.
# Swap breaks this contract. kubelet explicitly refuses to start if swap is on.
# -----------------------------------------------------------------------------
echo "[1/3] Disabling swap..."
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
echo "Swap status (should show 0):"
free -h | grep Swap

# -----------------------------------------------------------------------------
# LOAD KERNEL MODULES
# Why: 
#   overlay    — enables container filesystem layering (image layers)
#   br_netfilter — lets iptables inspect bridged network traffic
#                  required for pod-to-pod networking rules to apply
# -----------------------------------------------------------------------------
echo "[2/3] Loading kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Verify modules loaded
lsmod | grep overlay
lsmod | grep br_netfilter
echo "Kernel modules loaded successfully"

# -----------------------------------------------------------------------------
# SYSCTL NETWORK SETTINGS
# Why: Routes bridged IPv4/IPv6 traffic through iptables.
# Without this, pod-to-pod and pod-to-service traffic bypasses all
# Kubernetes network rules — nothing works.
# -----------------------------------------------------------------------------
echo "[3/3] Applying sysctl network settings..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

echo ""
echo "============================================="
echo " Prerequisites complete. Proceed to 02-containerd.sh"
echo "============================================="



