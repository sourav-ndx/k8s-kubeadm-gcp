# Kubernetes Cluster Upgrade — Easy's Everyday Guide
## Upgrading from v1.28 to v1.29 using kubeadm

This document explains the upgrade process in plain English — what each step does, why it exists, and what breaks if you skip it. Based on a real upgrade performed on this cluster.

---

## The Analogy — Office Building Elevator System

Think of your Kubernetes cluster like an office building with an elevator system.

| Elevator System | Kubernetes |
|:---|:---|
| Elevator control room | Control plane (brain of cluster) |
| Elevator cars | Worker nodes (where pods run) |
| Manufacturer's engineer | kubeadm (the upgrade tool) |
| Control panel | kube-apiserver |
| Motor | etcd (the database) |
| Floor selector | kube-scheduler |
| Safety system | kube-controller-manager |
| The car itself | kubelet (runs on each node) |

Each part must be upgraded in a specific order. You cannot upgrade the car before the control room — the car won't know how to talk to the new control system.

---

## Why You Cannot Just Press "Update All"

The elevator system has parts from different suppliers upgraded in strict order. Similarly Kubernetes has components that depend on each other. Upgrading in the wrong order breaks communication between components.

The correct order is always:
```
1. Add new repo          (get new tools delivered)
2. Upgrade kubeadm       (upgrade the engineer)
3. Upgrade control plane (engineer upgrades the control room)
4. Upgrade kubelet       (upgrade each elevator car manually)
```

---

## Step by Step — What Each Step Does

### Step 1 — Change the Repository

**The toolbox analogy:**
kubeadm is an engineer who carries tools for a specific version. He has a v1.28 toolbox. To do v1.29 work you must give him the v1.29 toolbox first.

The repository is that toolbox supplier. Changing the repo = calling the v1.29 supplier and getting new tools delivered.

```bash
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
```

Without this: apt says "I have never heard of v1.29" — because it is still talking to the v1.28 supplier only.

---

### Step 2 — Check Available Versions

```bash
apt-cache madison kubeadm | head -5
```

Shows what v1.29.x patch versions are available. Always pick the highest patch number — it has all bug fixes and security patches accumulated since 1.29.0.

In our cluster: latest was **1.29.15-1.1**

---

### Step 3 — Upgrade kubeadm

```bash
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.29.15-1.1
sudo apt-mark hold kubeadm
```

The engineer himself is now v1.29 capable. He can now upgrade everything else to v1.29.

Why unhold first: we held kubeadm during installation to prevent accidental upgrades. Now we deliberately unhold, upgrade, then hold again.

---

### Step 4 — Run Upgrade Plan

```bash
sudo kubeadm upgrade plan
```

Before touching anything the engineer does a full inspection:
- Is the cluster healthy right now?
- What version is everything at currently?
- What will it become after upgrade?
- Are there any manual steps needed?
- What is the exact command to run?

**Our output showed:**
```
Cluster version:  v1.28.15   ← current
Target version:   v1.29.15   ← destination
Manual upgrade:   NO         ← clean path
```

If upgrade plan shows errors — STOP. Never apply on a broken cluster.

---

### Step 5 — Apply the Upgrade (Control Plane Only)

```bash
sudo kubeadm upgrade apply v1.29.15
```

The engineer upgrades everything in the control room:

| Component | Before | After |
|:---|:---|:---|
| kube-apiserver | v1.28.15 | v1.29.15 |
| kube-controller-manager | v1.28.15 | v1.29.15 |
| kube-scheduler | v1.28.15 | v1.29.15 |
| kube-proxy | v1.28.15 | v1.29.15 |
| CoreDNS | v1.10.1 | v1.11.1 |
| etcd | 3.5.15 | 3.5.16 |

One command. kubeadm handles order, restarts, certificate renewal — everything.

**kubelet is NOT upgraded here.** See Step 7 for why.

---

### Step 6 — Drain the Node

```bash
kubectl drain k8s-control --ignore-daemonsets
```

Before upgrading kubelet, move all pods off this node safely.

**Why:** When kubelet restarts during upgrade, for 30-60 seconds the node is unmanaged. Any pod running there is at risk of being killed abruptly. Drain moves pods away first so upgrade is safe.

`--ignore-daemonsets`: DaemonSet pods (calico-node, kube-proxy) cannot be evicted — they are supposed to run on every node. Drain ignores them.

After drain: node is **cordoned** (SchedulingDisabled) — no new pods land here.

---

### Step 7 — Upgrade kubelet and kubectl

```bash
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.29.15-1.1 kubectl=1.29.15-1.1
sudo apt-mark hold kubelet kubectl
```

**Why kubelet is separate from everything else:**

All other components (apiserver, scheduler, etcd) run as containers inside Kubernetes. kubeadm can manage them directly.

kubelet is different. It runs directly on the Linux OS as a systemd service. It is the thing that STARTS containers. You cannot use Kubernetes to upgrade the component that runs Kubernetes — chicken and egg problem.

So kubelet must be upgraded manually via apt like any other Linux package.

```
Everything else = containers = kubeadm handles
kubelet         = Linux service = you handle via apt
```

---

### Step 8 — Restart kubelet

```bash
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

`daemon-reload`: tells systemd to re-read service files — kubelet's service file may have changed with the new version.

`restart kubelet`: applies the new version. Node briefly unmanaged during restart — this is why we drained first.

---

### Step 9 — Uncordon the Node

```bash
kubectl uncordon k8s-control
```

Removes the SchedulingDisabled mark. Node is back in rotation. New pods can schedule here again.

---

### Step 10 — Verify Control Plane

```bash
kubectl get nodes
```

```
NAME          STATUS   ROLES           VERSION
k8s-control   Ready    control-plane   v1.29.15  ✅
k8s-worker1   Ready    worker          v1.28.15  ← not upgraded yet, correct
```

Worker still shows v1.28.15 — this is correct and expected at this point.

---

### Step 11 — Drain Worker (from control plane)

```bash
kubectl drain k8s-worker1 --ignore-daemonsets --delete-emptydir-data
```

`--delete-emptydir-data`: worker nodes run actual application pods which may use emptyDir volumes. This flag allows draining even if those exist. Without it drain refuses.

**What we saw in our cluster:**
All 5 application pods (nginx x2, webapp x3) went to Pending state — because with only one worker there was nowhere else to go. In production with multiple workers, pods reschedule to other workers and users see zero downtime.

---

### Step 12 — On Worker Node — Add Repo and Upgrade kubeadm

```bash
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.29.15-1.1
sudo apt-mark hold kubeadm
```

Worker also needs the new repo and new kubeadm — even though it runs a lighter upgrade command.

---

### Step 13 — On Worker Node — kubeadm upgrade node

```bash
sudo kubeadm upgrade node
```

This is DIFFERENT from `upgrade apply`. 

`upgrade apply` — runs on control plane — upgrades apiserver, etcd, scheduler, controller-manager.

`upgrade node` — runs on workers — only updates the local kubelet configuration file. Workers have no control plane components to upgrade.

**Our output showed:**
```
Skipping phase. Not a control plane node.   ← correct
Writing kubelet configuration to file       ← only thing it does
```

---

### Step 14 — On Worker — Upgrade kubelet and kubectl

```bash
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.29.15-1.1 kubectl=1.29.15-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

Same as control plane — kubelet is a Linux service, upgraded via apt.

---

### Step 15 — Uncordon Worker (from control plane)

```bash
kubectl uncordon k8s-worker1
```

Worker back in rotation. Pods immediately reschedule from Pending to Running.

---

### Step 16 — Final Verification

```bash
kubectl get nodes
kubectl get pods -o wide
```

```
NAME          STATUS   ROLES           VERSION
k8s-control   Ready    control-plane   v1.29.15  ✅
k8s-worker1   Ready    worker          v1.29.15  ✅

NAME                    READY   STATUS    NODE
nginx-xxx               1/1     Running   k8s-worker1
webapp-xxx              1/1     Running   k8s-worker1
```

Both nodes upgraded. All pods Running. Zero data loss.

---

## The Full Picture

```
BEFORE UPGRADE:
  k8s-control  v1.28  [apiserver|etcd|scheduler|kubelet]
  k8s-worker1  v1.28  [kubelet + all pods]

PHASE 1 — CONTROL PLANE:
  Add v1.29 repo → upgrade kubeadm → upgrade plan → upgrade apply
  k8s-control  [apiserver✅|etcd✅|scheduler✅|kubelet❌ still 1.28]

  Drain → upgrade kubelet via apt → restart → uncordon
  k8s-control  v1.29 FULLY UPGRADED ✅

PHASE 2 — WORKER:
  Drain worker → pods go Pending (nowhere to go, single worker)
  Add v1.29 repo → upgrade kubeadm → kubeadm upgrade node
  Upgrade kubelet via apt → restart → uncordon
  k8s-worker1  v1.29 FULLY UPGRADED ✅
  Pods return to Running ✅

AFTER UPGRADE:
  k8s-control  v1.29.15  Ready  ✅
  k8s-worker1  v1.29.15  Ready  ✅
```

---

## Key Rules to Remember

**One minor version at a time:**
1.28 → 1.29 only. Never 1.28 → 1.30. Kubernetes guarantees compatibility only for N-1 versions. Skipping versions can corrupt etcd or break API calls silently.

**Control plane before workers:**
Workers talk to the API server constantly. API server must be on new version before workers upgrade to it.

**Always run upgrade plan first:**
Never apply on a broken cluster. Upgrade plan is your safety check.

**kubelet is always manual:**
It runs outside Kubernetes as a Linux service. Always upgraded via apt, always requires drain before restart.

**Always drain before upgrading kubelet:**
Pods must be off the node before the node agent restarts. No exceptions.

---
