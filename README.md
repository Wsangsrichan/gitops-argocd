# gitops-argocd

![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-blue?logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.32.1-blue?logo=kubernetes)
![ArgoCD](https://img.shields.io/badge/ArgoCD-v2.14_HA-orange)
![DigitalOcean](https://img.shields.io/badge/DigitalOcean-6_Nodes-0080ff?logo=digitalocean)

Production GitOps deployment of ArgoCD HA on a 6-node DigitalOcean Kubernetes cluster.
All workloads sync automatically from this GitHub repo via the App of Apps pattern.

## Table of Contents

- [Quick Access](#quick-access)
- [Architecture](#architecture)
- [Directory Structure](#directory-structure)
- [Deployment](#deployment)
- [Getting Started (from scratch)](#getting-started-from-scratch)
- [Troubleshooting](#troubleshooting)
- [Known Issues](#known-issues)
- [Sync Policy](#sync-policy)
- [Phase History](#phase-history)
- [Uninstall](#uninstall)

## Quick Access

| Service | URL | Auth |
|---------|-----|------|
| ArgoCD (HA) | https://argocd.ipptt.com | admin / `(initial-secret)` |
| Guestbook | https://guestbook.ipptt.com | — |
| Nginx Demo | https://nginx.ipptt.com | — |
| Grafana | https://grafana.ipptt.com | admin / admin |

Get ArgoCD admin password:
```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

## Architecture

6-node DO cluster (3 control plane + 3 workers), K8s v1.32.1, Calico VXLAN networking.
ArgoCD v2.14 runs in HA mode with Redis HA (sentinel-based failover), 8 pods total.
NGINX Ingress Controller exposes 4 services on `*.ipptt.com`.
All manifests live in this repo — ArgoCD auto-syncs on every push (prune + selfHeal).

## Directory Structure

```
gitops-argocd/
├── bootstrap/                  # ArgoCD install + scripts
│   ├── install.sh
│   ├── uninstall.sh
│   ├── namespace.yaml
│   └── install.yaml            # ArgoCD v2.14 HA manifest
├── projects/
│   └── demo-project.yaml       # RBAC-bounded demo project
├── apps/                       # Application definitions
│   ├── guestbook/              # Helm-based demo
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── templates/
│   │   └── Application.yaml
│   └── nginx-demo/             # Kustomize-based demo
│       ├── base/
│       └── Application.yaml
├── argocd/
│   └── root-app.yaml           # App of Apps (auto-sync)
├── infra/                      # Infrastructure components
│   ├── ingress/                # NGINX Ingress rules (*.ipptt.com)
│   │   ├── argocd.yaml
│   │   ├── guestbook.yaml
│   │   ├── nginx-demo.yaml
│   │   └── grafana.yaml
│   ├── monitoring/             # Prometheus + Grafana Helm values
│   └── quotas/                 # ResourceQuota manifests
├── sealed-secrets/             # SealedSecrets v0.28
├── resource-quotas/            # Alternative quota location
├── ingress/                    # Alternative ingress location
├── .planning/                  # GSD planning documents
│   └── phases/
│       ├── 02-deploy/
│       ├── 03-ingress-monitoring/
│       └── 04-production-deploy/
└── CLAUDE.md                   # Project documentation
```

## Deployment

### Prerequisites

- Kubernetes v1.32+ cluster (6-node DigitalOcean)
- `kubectl` configured with cluster admin access
- NGINX Ingress Controller installed (NodePort 80:32431, 443:30364)
- Default StorageClass available for PVCs
- HA Proxy at `178.128.104.161:8443` for API server access

### DNS Workaround

Inter-node port 53 is blocked on this cluster. All ArgoCD pods run on a single node.

```bash
# Scale CoreDNS to 1 replica
kubectl scale deployment coredns -n kube-system --replicas=1

# Remove control plane taints
kubectl taint nodes controlplan-0 node-role.kubernetes.io/control-plane:NoSchedule-

# Pin ArgoCD pods to controlplan-0 (nodeSelector in manifests)
# All 8 ArgoCD pods scheduled on controlplan-0
```

### ArgoCD HA Install

```bash
# Apply HA manifest
kubectl apply -f bootstrap/install.yaml -n argocd

# Scale to 1 replica (DNS workaround — single node)
kubectl scale deployment argocd-server -n argocd --replicas=1
kubectl scale deployment argocd-repo-server -n argocd --replicas=1
kubectl scale statefulset argocd-application-controller -n argocd --replicas=1
```

Redis HA uses sentinel-based failover:
```
argocd-server → argocd-redis-ha-haproxy:26379 → argocd-redis-ha-server:6379
```

### Ingress Setup

4 Ingress hosts on `*.ipptt.com`:

```bash
kubectl apply -f infra/ingress/
```

| Host | Backend | Namespace |
|------|---------|-----------|
| argocd.ipptt.com | argocd-server | argocd |
| guestbook.ipptt.com | guestbook | guestbook |
| nginx.ipptt.com | nginx-demo | nginx-demo |
| grafana.ipptt.com | grafana | monitoring |

### GitOps Deploy

Public repo — no PAT required. ArgoCD connects anonymously.

```bash
# Create AppProject
kubectl apply -f projects/demo-project.yaml

# Deploy root app (App of Apps pattern)
kubectl apply -f argocd/root-app.yaml

# Verify
argocd app list
kubectl get pods -n argocd
```

### Infrastructure

| Component | Version | Method |
|-----------|---------|--------|
| SealedSecrets | v0.28 | Controller in `sealed-secrets` namespace |
| Prometheus | standalone | Helm chart, `monitoring` namespace |
| Grafana | Helm | `monitoring` namespace, admin/admin |
| ResourceQuotas | — | Applied to `guestbook` + `nginx-demo` namespaces |

## Getting Started (from scratch)

Step-by-step guide for deploying on any Kubernetes cluster. Adapt the DNS workaround if needed.

### 0. Verify Prerequisites

```bash
kubectl cluster-info
kubectl get nodes
argocd version --client
```

### 1. Install ArgoCD

```bash
# Option A: One-command
chmod +x bootstrap/install.sh
./bootstrap/install.sh

# Option B: Manual
kubectl create namespace argocd
kubectl apply -n argocd -f bootstrap/install.yaml
kubectl get pods -n argocd -w
```

### 2. Access Dashboard

```bash
# Get admin password
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d && echo

# With Ingress (production):
open https://argocd.ipptt.com

# Without Ingress (dev):
kubectl port-forward svc/argocd-server -n argocd 8080:443
open https://localhost:8080
```

Login: `admin` / *(output above)* — browser will show self-signed cert warning on first access.

### 3. Login via CLI

```bash
PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d)

argocd login argocd.ipptt.com --username admin --password "${PASSWORD}" --insecure --grpc-web
```

### 4. Connect Repo

Public repo — no PAT needed:

```bash
argocd repo add https://github.com/Wsangsrichan/gitops-argocd.git --type git
```

For private repos, use SealedSecrets or `argocd repo add` with credentials.

### 5. Create AppProject

```bash
kubectl apply -f projects/demo-project.yaml
argocd proj list
```

### 6. Deploy Demo Apps

```bash
# App of Apps (recommended)
kubectl apply -f argocd/root-app.yaml

# Or individual apps
kubectl apply -f apps/guestbook/Application.yaml
kubectl apply -f apps/nginx-demo/Application.yaml
```

### 7. Check Status

```bash
argocd app list
argocd app get guestbook
argocd app get nginx-demo
```

Expected: `OutOfSync` / `Missing` — normal before first sync.

### 8. Sync Applications

```bash
# Sync all
argocd app sync root-app --cascade

# Or individual
argocd app sync guestbook
argocd app sync nginx-demo
```

Auto-sync (prune + selfHeal) is enabled by default — apps will sync automatically on every push.

### 9. Verify Workloads

```bash
kubectl get pods -n guestbook
kubectl get pods -n nginx-demo

# With Ingress:
curl -H "Host: guestbook.ipptt.com" http://<ingress-ip>/
curl -H "Host: nginx.ipptt.com" http://<ingress-ip>/

# Without Ingress:
kubectl port-forward svc/guestbook -n guestbook 8081:80
kubectl port-forward svc/nginx-demo -n nginx-demo 8082:80
```

## Troubleshooting

### Pods stuck in Pending/ContainerCreating

```bash
kubectl describe pod <pod-name> -n argocd
# Common causes: insufficient resources, image pull issues, PVC problems
```

### Repo connection fails

```bash
kubectl run tmp --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s -o /dev/null -w "%{http_code}" https://github.com/Wsangsrichan/gitops-argocd.git

argocd repo add https://github.com/Wsangsrichan/gitops-argocd.git --type git --upsert
```

### Application stuck OutOfSync

```bash
argocd app diff <app-name>
argocd app get <app-name> --hard-refresh
kubectl get all -n <target-namespace>
```

### Reset admin password

```bash
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {"admin.password": "'"$(htpasswd -nbBC 10 admin NEW_PASSWORD | tr -d ':\n' | sed 's/$2y/$2a/')"'"}}'
```

## Known Issues

| Issue | Workaround | Fix |
|-------|-----------|-----|
| Inter-node DNS blocked (port 53) | CoreDNS=1 + ArgoCD pinned to controlplan-0 | Open UDP/TCP 53 on DO firewall |
| HA replicas scaled to 1 | Pod anti-affinity + single-node limit | Scale after DNS fix |
| Grafana datasource manual | Connect Prometheus at `http://prometheus-server.monitoring.svc.cluster.local` | Provision via ConfigMap |

## Sync Policy

Auto-sync enabled — `automated.prune: true`, `automated.selfHeal: true`.
ArgoCD syncs from GitHub on every push. No manual sync needed.

## Phase History

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Bootstrap ArgoCD core | ✅ |
| Phase 2 | AppProjects + demo apps | ✅ |
| Phase 2b | SealedSecrets + Auto-Sync | ✅ |
| Phase 3 | Ingress + Monitoring + Quotas | ✅ |
| Phase 4 | HA redeploy (6-node DO, ipptt.com, Redis HA) | ✅ |

## Repo

**https://github.com/Wsangsrichan/gitops-argocd.git** — public, no authentication needed.

## Uninstall

```bash
chmod +x bootstrap/uninstall.sh
./bootstrap/uninstall.sh
```

## License

Internal use — Haocomm
