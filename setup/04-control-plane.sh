#!/bin/bash
# =============================================================================
# 04-control-plane.sh
# Run on CONTROL PLANE NODE ONLY
# Initialises the Kubernetes control plane using kubeadm
# Author: Sourav Nandy | github.com/sourav-ndx
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# CONFIGURATION — edit these before running
# -----------------------------------------------------------------------------
POD_CIDR="192.168.0.0/16"       # Pod network — must not overlap node or service CIDRs
                                  # 192.168.0.0/16 matches Calico default
SERVICE_CIDR="10.96.0.0/12"     # Service network — kubeadm default, change if conflicts
CONTROL_PLANE_IP=$(hostname -I | awk '{print $1}')  # Auto-detect private IP

echo "============================================="
echo " STEP 4: Initialise Control Plane"
echo " Run on CONTROL PLANE NODE ONLY"
echo "============================================="
echo ""
echo "Configuration:"
echo "  Control Plane IP : ${CONTROL_PLANE_IP}"
echo "  Pod CIDR         : ${POD_CIDR}"
echo "  Service CIDR     : ${SERVICE_CIDR}"
echo ""
read -p "Confirm and proceed? (y/n): " confirm
[[ "$confirm" != "y" ]] && echo "Aborted." && exit 1

# -----------------------------------------------------------------------------
# KUBEADM INIT
# --pod-network-cidr: IP range for pods assigned by Calico CNI
#   Must not overlap: node network or service CIDR
#   192.168.0.0/16 chosen to match Calico's default expectation
#
# --apiserver-advertise-address: Private IP worker nodes use to reach
#   the API server on port 6443. Must be the internal/private IP.
#
# --service-cidr: Virtual IP range for Services (ClusterIP)
#   These are NOT real interfaces — kube-proxy handles iptables rules
# -----------------------------------------------------------------------------
echo "[1/3] Running kubeadm init..."
sudo kubeadm init \
  --pod-network-cidr=${POD_CIDR} \
  --service-cidr=${SERVICE_CIDR} \
  --apiserver-advertise-address=${CONTROL_PLANE_IP}

# -----------------------------------------------------------------------------
# CONFIGURE KUBECTL
# kubeadm creates admin.conf owned by root at /etc/kubernetes/admin.conf
# We copy it to the user's home so kubectl works without sudo
# -----------------------------------------------------------------------------
echo "[2/3] Configuring kubectl access..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
echo "kubectl configured at $HOME/.kube/config"

# Verify control plane is up (will show NotReady — CNI not installed yet)
echo ""
echo "Node status (NotReady is expected — CNI not installed yet):"
kubectl get nodes

# -----------------------------------------------------------------------------
# PRINT JOIN COMMAND
# Save this — worker nodes need it to join the cluster
# Token expires after 24 hours. Regenerate with:
# kubeadm token create --print-join-command
# -----------------------------------------------------------------------------
echo ""
echo "[3/3] Generating worker join command..."
echo ""
echo "============================================="
echo " SAVE THIS JOIN COMMAND FOR WORKER NODES:"
echo "============================================="
kubeadm token create --print-join-command
echo "============================================="
echo ""
echo " Next: run 05-calico.sh to install CNI"
echo "============================================="
