# Kubernetes Networking — Deep Dive
## Three IP Spaces Explained

This document explains the networking model in this cluster based on what we actually observed running live.

---

## The Three IP Spaces

Every Kubernetes cluster has three completely separate IP ranges. Understanding this is fundamental to debugging any connectivity issue.

### 1. Node Network — 10.128.0.x (GCP assigned)

These are the real IP addresses of the Linux VMs. GCP's VPC subnet in us-central1 uses 10.128.0.0/20 and assigns IPs automatically when VMs are created.

- `k8s-control` → `10.128.0.2`
- `k8s-worker1` → `10.128.0.3`

**Owner:** GCP. Nothing to do with Kubernetes.

---

### 2. Pod Network — 192.168.x.x (Calico assigned)

We defined this range with `--pod-network-cidr=192.168.0.0/16` during `kubeadm init`. Calico CNI carves this into per-node blocks:

- Worker node gets block: `192.168.194.0/24`
- Pods on that node get IPs: `.65`, `.66`, `.67`, `.68`, `.69`...

If a second worker is added, Calico assigns it a different block — e.g. `192.168.195.0/24`. No IP conflicts across nodes.

**Owner:** You (defined at cluster init). Managed by Calico.

---

### 3. Service Network — 10.96.x.x (kube-proxy virtual)

Services get IPs from the service CIDR — `10.96.0.0/12` (kubeadm default).

**These IPs are not real.** No network interface on any machine has these IPs. They exist only as iptables rules programmed by kube-proxy on every node.

**Owner:** kube-proxy. Pure Linux kernel iptables.

---

## How Traffic Actually Flows

### Pod-to-Pod (same node)
```
Pod A (192.168.194.65) → Pod B (192.168.194.66)
Traffic stays on the node via Linux bridge
Calico manages the bridge and routing table
```

### Pod-to-Pod (different nodes)
```
Pod A on worker1 (192.168.194.65)
  → Calico routes via BGP or VXLAN to worker2
  → Pod B on worker2 (192.168.195.65)
```

### Pod-to-Service (ClusterIP)
```
Pod sends traffic to 10.108.19.210:80 (ClusterIP)
  → iptables KUBE-SERVICES chain intercepts
  → Probability chain selects a pod IP
  → Traffic redirected to 192.168.194.65:80 (actual pod)
```

### External-to-NodePort
```
curl http://10.128.0.3:30273
  → Hits worker node real IP on NodePort
  → KUBE-NODEPORTS iptables rule matches
  → KUBE-SVC chain load balances to a pod
  → Pod responds, SNAT rewrites source for return path
```

---

## kube-proxy iptables — Observed Live

```bash
sudo iptables -t nat -L KUBE-SVC-XYE2YDI3XU6DYWMQ
```

```
KUBE-MARK-MASQ  !192.168.0.0/16  10.110.211.25   # SNAT external traffic
KUBE-SEP-FOP5   probability 0.33333333349         # → 192.168.194.67:80
KUBE-SEP-HA22   probability 0.50000000000         # → 192.168.194.68:80
KUBE-SEP-D7PC   (no probability = remaining)      # → 192.168.194.69:80
```

**The math:**
- Rule 1: 33.3% → Pod 1
- Rule 2: 50% of remaining 66.7% = 33.3% → Pod 2
- Rule 3: remaining 33.3% → Pod 3
- **Result: perfectly equal distribution**

This is stateless probability — not round-robin. Each packet independently rolls the dice.

---

## Why Services Use iptables Not a Real Proxy

The name `kube-proxy` is misleading. In modern Kubernetes (iptables mode), it does not actually proxy traffic. Instead:

1. kube-proxy watches the API server for Service and Endpoint changes
2. For every change, it programs iptables rules on the local node
3. The Linux kernel itself intercepts matching packets and redirects them
4. Zero userspace hops — pure kernel networking

**Performance implication:** Service routing adds near-zero latency. No process handles the packet — the kernel does it inline during normal IP routing.

---

## Why SIP Traffic Needs F5, Not K8s Services

Kubernetes Service load balancing is stateless — each packet independently selects a pod. For HTTP this is fine — each request is independent.

For SIP (Session Initiation Protocol):
- A call is a stateful session — INVITE, ACK, BYE must all reach the same backend pod
- If mid-call packets route to different pods, the call drops
- Kubernetes probability-based iptables would break SIP sessions under load

**Solution:** F5 BIG-IP with Source IP persistence. F5 remembers which pod a SIP session started on and routes all subsequent packets for that session to the same pod — regardless of load balancing decisions for new sessions.

This is why in production telecom Kubernetes deployments, F5 handles SIP while Kubernetes Services handle stateless HTTP microservices.

---

## SNAT — The KUBE-MARK-MASQ Rule Explained

```
KUBE-MARK-MASQ  tcp  -- !192.168.0.0/16  10.110.211.25
```

The `!` means NOT. Traffic from outside the pod network hitting the Service IP gets marked for SNAT (Source NAT). The source IP gets rewritten to the node IP before the packet reaches the pod.

**Why:** The pod needs to know where to send the response. If the original source IP is preserved, the pod tries to respond directly to the client — but the client never opened a connection to the pod IP, only to the Service IP. SNAT ensures responses go back through the node which reverse-NATs them correctly.

Traffic already inside the pod network (`192.168.x.x`) doesn't need SNAT — it can route back directly.

---

## Debugging Connectivity — Layer by Layer

When a pod can't reach a service, always work layer by layer:

```bash
# Layer 1: Is the pod running?
kubectl get pods -n <ns> -l app=<label>

# Layer 2: Does the Service have endpoints?
kubectl get endpoints <svc-name> -n <ns>
# If empty → label selector mismatch between Service and Pod

# Layer 3: Can you reach pod directly?
kubectl exec -it <debug-pod> -- curl http://<pod-ip>:<port>

# Layer 4: Can you reach via Service ClusterIP?
kubectl exec -it <debug-pod> -- curl http://<cluster-ip>:<port>

# Layer 5: Check iptables rules exist
sudo iptables -t nat -L KUBE-SERVICES | grep <service-name>

# Layer 6: Check NetworkPolicy
kubectl get networkpolicy -n <ns>
```


