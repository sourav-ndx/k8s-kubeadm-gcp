#!/bin/bash
# =============================================================================
# 05-calico.sh
# Run on CONTROL PLANE NODE ONLY after kubeadm init
# Installs Calico CNI — pod networking and NetworkPolicy enforcement
# Author: Sourav Nandy | github.com/sourav-ndx
# =============================================================================

set -e

CALICO_VERSION="v3.26.1"

echo "============================================="
echo " STEP 5: Install Calico CNI"
echo " Run on CONTROL PLANE NODE ONLY"
echo "============================================="
echo ""
echo "Why Calico:"
echo "  - Production-grade CNI with NetworkPolicy enforcement"
echo "  - Assigns pod IPs from your pod-network-cidr (192.168.0.0/16)"
echo "  - Runs as DaemonSet — one calico-node pod per node"
echo "  - Nodes stay NotReady until this is installed"
echo ""

# -----------------------------------------------------------------------------
# INSTALL CALICO
# This applies the Calico manifest which creates:
#   - calico-node DaemonSet (one pod per node — manages networking)
#   - calico-kube-controllers Deployment
#   - Required CRDs, RBAC, ConfigMaps
# -----------------------------------------------------------------------------
echo "[1/2] Applying Calico manifest..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml
echo "Calico manifest applied"

# -----------------------------------------------------------------------------
# WAIT FOR NODES TO BECOME READY
# After Calico pods start, nodes transition from NotReady to Ready
# Usually takes 2-3 minutes
# -----------------------------------------------------------------------------
echo ""
echo "[2/2] Waiting for nodes to become Ready..."
echo "This takes 2-3 minutes. Watching..."
echo ""

kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo ""
echo "============================================="
echo " Node status:"
kubectl get nodes
echo ""
echo " Calico pods:"
kubectl get pods -n kube-system -l k8s-app=calico-node
echo ""
echo " All system pods:"
kubectl get pods -A
echo "============================================="
echo " CNI installed. Now join worker nodes."
echo " Then run 06-verify.sh to validate the cluster."
echo "============================================="
