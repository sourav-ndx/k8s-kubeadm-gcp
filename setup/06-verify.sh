#!/bin/bash
# =============================================================================
# 06-verify.sh
# Run on CONTROL PLANE NODE after all nodes joined
# Verifies cluster health and deploys test workloads
# Author: Sourav Nandy | github.com/sourav-ndx
# =============================================================================

echo "============================================="
echo " STEP 6: Verify Cluster Health"
echo "============================================="

# Node status
echo ""
echo "[CHECK 1] Node status:"
kubectl get nodes -o wide

# All system pods
echo ""
echo "[CHECK 2] System pods (all should be Running):"
kubectl get pods -A

# Cluster info
echo ""
echo "[CHECK 3] Cluster info:"
kubectl cluster-info

# -----------------------------------------------------------------------------
# DEPLOY TEST WORKLOAD
# Deploys nginx to verify:
#   - Scheduler works (pod placed on worker)
#   - CNI works (pod gets IP from pod CIDR)
#   - Service routing works (NodePort accessible)
# -----------------------------------------------------------------------------
echo ""
echo "[CHECK 4] Deploying test workload (nginx)..."
kubectl create deployment nginx --image=nginx --replicas=2 2>/dev/null || \
  echo "nginx deployment already exists"

kubectl expose deployment nginx --type=NodePort --port=80 2>/dev/null || \
  echo "nginx service already exists"

echo "Waiting for pods to be Running..."
kubectl wait --for=condition=Ready pod -l app=nginx --timeout=60s

echo ""
echo "Pod placement (should be on worker node, not control plane):"
kubectl get pods -o wide -l app=nginx

echo ""
echo "Service details:"
kubectl get svc nginx

WORKER_IP=$(kubectl get nodes -o wide | grep worker | awk '{print $6}')
NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')

echo ""
echo "[CHECK 5] Testing HTTP access..."
if curl -s --connect-timeout 5 http://${WORKER_IP}:${NODE_PORT} | grep -q "Welcome to nginx"; then
  echo "SUCCESS: nginx responding at http://${WORKER_IP}:${NODE_PORT}"
else
  echo "NOTE: Direct curl may not work from control plane without firewall rule"
  echo "Test manually: curl http://${WORKER_IP}:${NODE_PORT}"
fi

# -----------------------------------------------------------------------------
# SHOW IPTABLES LOAD BALANCING
# Demonstrates kube-proxy iptables rules for the nginx service
# -----------------------------------------------------------------------------
echo ""
echo "[CHECK 6] kube-proxy iptables rules for nginx service:"
CHAIN=$(sudo iptables -t nat -L KUBE-SERVICES 2>/dev/null | grep nginx | awk '{print $1}')
if [ -n "$CHAIN" ]; then
  sudo iptables -t nat -L ${CHAIN} 2>/dev/null
fi

echo ""
echo "============================================="
echo " Cluster verification complete"
echo ""
echo " Three IP spaces in this cluster:"
echo "   Node network   : $(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' | cut -d. -f1-3).0/20 (GCP VPC)"
echo "   Pod network    : 192.168.0.0/16 (Calico)"
echo "   Service network: 10.96.0.0/12 (kube-proxy)"
echo "============================================="

