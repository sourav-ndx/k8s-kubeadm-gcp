<div align="center">

# 🚀 Kubernetes Cluster from Scratch
### Built with kubeadm on Google Cloud Platform

> 2-node cluster | Kubernetes v1.28 | Calico CNI | GCP e2-medium | Built from scratch

![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.28-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Calico](https://img.shields.io/badge/CNI-Calico_v3.26-F8861A?style=for-the-badge)
![GCP](https://img.shields.io/badge/GCP-Compute_Engine-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)
![containerd](https://img.shields.io/badge/Runtime-containerd-575757?style=for-the-badge)
![Status](https://img.shields.io/badge/Cluster-Active-brightgreen?style=for-the-badge)

</div>

---

## 📁 Repository Structure

```
k8s-kubeadm-gcp/
├── setup/
│   ├── 01-prerequisites.sh     # Swap, kernel modules, sysctl — both nodes
│   ├── 02-containerd.sh        # Container runtime install and config — both nodes
│   ├── 03-k8s-install.sh       # kubeadm, kubelet, kubectl — both nodes
│   ├── 04-control-plane.sh     # kubeadm init — control plane only
│   ├── 05-calico.sh            # Calico CNI install — control plane only
│   └── 06-verify.sh            # Cluster health check and test deployment
├── manifests/
│   ├── nginx-deployment.yaml   # nginx — 2 replicas with probes and resource limits
│   ├── nginx-service.yaml      # NodePort Service for nginx
│   ├── webapp-deployment.yaml  # Apache httpd — 3 replicas
│   └── webapp-service.yaml     # NodePort Service for webapp
├── docs/
│   ├── networking-explained.md # Three IP spaces, iptables internals, SIP context
│   └── github-setup.md         # Push from GCP VM to GitHub
└── README.md
```

---

## ⚡ Quick Start

```bash
git clone git@github.com:sourav-ndx/k8s-kubeadm-gcp.git
cd k8s-kubeadm-gcp
chmod +x setup/*.sh

# Run on BOTH nodes (control plane + worker):
bash setup/01-prerequisites.sh
bash setup/02-containerd.sh
bash setup/03-k8s-install.sh

# Run on CONTROL PLANE only:
bash setup/04-control-plane.sh
bash setup/05-calico.sh

# Join worker node using the command printed by 04-control-plane.sh
# Then verify from control plane:
bash setup/06-verify.sh
```

---

## 📐 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                  GCP VPC — us-central1-a                        │
│                  Node Network: 10.128.0.0/20                    │
│                                                                 │
│  ┌───────────────────────────┐  ┌───────────────────────────┐   │
│  │      k8s-control          │  │      k8s-worker1          │   │
│  │      10.128.0.2           │  │      10.128.0.3           │   │
│  │      e2-medium            │  │      e2-medium            │   │
│  │      2 vCPU / 4GB RAM     │  │      2 vCPU / 4GB RAM     │   │
│  │                           │  │                           │   │
│  │  kube-apiserver           │  │  kubelet                  │   │
│  │  etcd                     │  │  kube-proxy               │   │
│  │  kube-scheduler           │  │  calico-node              │   │
│  │  controller-manager       │  │                           │   │
│  │  calico-node              │  │  [nginx pods]             │   │
│  │  coredns                  │  │  [webapp pods]            │   │
│  └───────────────────────────┘  └───────────────────────────┘   │
│                                                                 │
│  Pod Network (Calico):    192.168.0.0/16                        │
│  Service Network:         10.96.0.0/12                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🌐 Three IP Spaces — The Core of K8s Networking

| Network | Range | Assigned By | Used By |
|:---|:---|:---|:---|
| **Node Network** | `10.128.0.0/20` | GCP VPC | Physical VMs |
| **Pod Network** | `192.168.0.0/16` | Calico CNI | Pod-to-pod communication |
| **Service Network** | `10.96.0.0/12` | kube-proxy / iptables | Virtual Service IPs |

> **Key Insight:** Service IPs (ClusterIP) are **not real interfaces**. No NIC holds them anywhere. kube-proxy programs iptables rules that intercept traffic to these IPs and redirect to actual pod IPs — pure Linux kernel networking, zero proxy overhead.

---

## 🧱 Stack

| Component | Version | Role |
|:---|:---|:---|
| **Kubernetes** | v1.28.15 | Container orchestration |
| **kubeadm** | v1.28.15 | Cluster bootstrap |
| **kubelet** | v1.28.15 | Node agent |
| **kubectl** | v1.28.15 | CLI |
| **containerd** | latest | Container runtime |
| **Calico** | v3.26.1 | CNI — pod networking + NetworkPolicy |
| **CoreDNS** | built-in | Cluster DNS |
| **GCP Compute Engine** | e2-medium | Infrastructure |

---

## ⚙️ Prerequisites — Both Nodes

### 1. Disable Swap
```bash
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
free -h
```
> kubelet refuses to start if swap is enabled. K8s scheduler assumes RAM is the only memory tier — swap breaks this contract.

### 2. Kernel Modules
```bash
cat <<KERNEL | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
KERNEL
sudo modprobe overlay && sudo modprobe br_netfilter
```
> `overlay` for container filesystem layers. `br_netfilter` lets iptables see bridged pod traffic.

### 3. Sysctl Settings
```bash
cat <<SYSCTL | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL
sudo sysctl --system
```
> Without this, pod-to-pod and pod-to-service traffic bypasses all K8s network rules.

---

## 🔧 Installation

### Step 1 — containerd (Both Nodes)
```bash
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd
```
> **`SystemdCgroup = true` is critical.** K8s and containerd must share the same cgroup driver. Mismatch causes kubelet to crash — most common kubeadm failure point.

### Step 2 — kubeadm + kubelet + kubectl (Both Nodes)
```bash
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```
> `apt-mark hold` prevents accidental upgrades. K8s upgrades are deliberate, one-minor-version operations — never automatic.

### Step 3 — Init Control Plane (Control Plane Only)
```bash
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --apiserver-advertise-address=<CONTROL_PLANE_PRIVATE_IP>

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Regenerate join command anytime:
kubeadm token create --print-join-command
```

### Step 4 — Calico CNI (Control Plane Only)
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
kubectl get nodes -w
```
> Nodes stay `NotReady` until CNI is installed. Calico assigns pod IPs and enforces NetworkPolicy.

### Step 5 — Join Worker (Worker Node Only)
```bash
sudo kubeadm join <CONTROL_PLANE_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

### Step 6 — Label and Verify
```bash
kubectl label node k8s-worker1 node-role.kubernetes.io/worker=worker
kubectl get nodes
```
```
NAME          STATUS   ROLES           AGE   VERSION
k8s-control   Ready    control-plane   22m   v1.28.15
k8s-worker1   Ready    worker           6m   v1.28.15
```

---

## 🚀 Test Deployments

```bash
# Deploy nginx — 2 replicas
kubectl apply -f manifests/nginx-deployment.yaml
kubectl apply -f manifests/nginx-service.yaml

# Deploy Apache webapp — 3 replicas
kubectl apply -f manifests/webapp-deployment.yaml
kubectl apply -f manifests/webapp-service.yaml

# Verify
kubectl get pods -o wide
kubectl get svc
curl http://<WORKER_NODE_IP>:<NODEPORT>
```

---

## 🔬 kube-proxy iptables — Load Balancing Internals

```bash
sudo iptables -t nat -L KUBE-SERVICES
sudo iptables -t nat -L KUBE-SVC-<CHAIN_NAME>
```

**Actual output from this cluster:**
```
KUBE-SEP-xxx  probability 0.33333333349  ->  192.168.194.67:80
KUBE-SEP-xxx  probability 0.50000000000  ->  192.168.194.68:80
KUBE-SEP-xxx  (remaining)               ->  192.168.194.69:80
```

**The math:** 33.3% + (50% of 66.7%) + (100% of 33.3%) = **33.3% per pod**

> K8s load balancing is stateless probability-based iptables — not round-robin. Each packet independently evaluates rules. This is why stateful protocols like SIP need F5 with source IP persistence — Kubernetes Services would break mid-call sessions by routing packets to different pods.

---

## 🧠 Control Plane Components

| Pod | Role | Impact if Down |
|:---|:---|:---|
| **etcd** | Cluster state database | Catastrophic — all state lost |
| **kube-apiserver** | Front door for all operations | No cluster operations possible |
| **kube-scheduler** | Assigns pods to nodes | New pods stay Pending |
| **controller-manager** | Reconciliation — recreates crashed pods | Pod failures not recovered |
| **coredns** | DNS resolution for Services | Pod DNS breaks |
| **calico-node** | CNI agent per node | Pod networking breaks on that node |
| **kube-proxy** | iptables rules for Services | Service routing fails |

---

## ⚖️ kubeadm vs Managed K8s

| | kubeadm (This Repo) | EKS / GKE / AKS |
|:---|:---:|:---:|
| Control plane SSH | ✅ Full | ❌ Hidden |
| etcd access | ✅ Direct | ❌ Abstracted |
| Component visibility | ✅ Every pod | ❌ Black box |
| Interview value | ✅ **"I built it"** | ❌ "I clicked a button" |
| Cost | ✅ Free tier VMs | ❌ ~$70/month (EKS) |

---

## 🔄 Cluster Lifecycle

```bash
# Restart cluster after VM reboot (both nodes):
sudo systemctl restart kubelet

# Reset a node cleanly:
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd ~/.kube
sudo systemctl restart containerd
```

---

## 📖 Further Reading

- [Networking Deep Dive](docs/networking-explained.md) — three IP spaces, iptables internals, SIP/F5 context
- [GitHub Setup from GCP](docs/github-setup.md) — push from GCP VM to GitHub
- [Cluster Upgrade Guide](docs/cluster-upgrade-explained.md) — v1.28 to v1.29, every step explained with a Mental Model referecne
---

## 🗺️ Roadmap

- [x] 2-node kubeadm cluster on GCP
- [x] Calico CNI — pod networking live
- [x] NodePort Services — external access verified
- [x] kube-proxy iptables inspection
- [x] Setup scripts and manifests
- [ ] ArgoCD — GitOps deployment pipeline
- [ ] Helm chart deployment
- [ ] NetworkPolicy implementation
- [ ] HPA with Metrics Server
- [x] Cluster upgrade v1.28 to v1.29
- [ ] Terraform — provision GCP infra as code

---

## 👤 Author

**Sourav Nandy** — Platform & DevOps Engineer | CKA Certified
Ericsson / Verizon | OpenShift Production SME | 9+ Years

[![LinkedIn](https://img.shields.io/badge/LinkedIn-sourav--nandy--0115-0A66C2?style=flat&logo=linkedin)](https://linkedin.com/in/sourav-nandy-0115)
[![GitHub](https://img.shields.io/badge/GitHub-sourav--ndx-181717?style=flat&logo=github)](https://github.com/sourav-ndx)

---

<div align="center">

*"Understanding what EKS hides from you is what makes you dangerous in an interview."*

⭐ Star this repo if it helped you understand Kubernetes internals

</div>
