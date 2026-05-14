# gitops-argocd

![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-blue?logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.32.1-blue?logo=kubernetes)
![ArgoCD](https://img.shields.io/badge/ArgoCD-v2.14-orange)

GitOps repository for ArgoCD on Kubernetes v1.32.1. Contains bootstrap manifests,
AppProjects, and Application definitions managed by ArgoCD.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 0 — Verify Prerequisites](#step-0--verify-prerequisites)
- [Step 1 — Install ArgoCD](#step-1--install-argocd)
- [Step 2 — Access Dashboard](#step-2--access-dashboard)
- [Step 3 — Login via CLI](#step-3--login-via-cli)
- [Step 4 — Connect GitLab Repo](#step-4--connect-gitlab-repo)
- [Step 5 — Create AppProject](#step-5--create-appproject)
- [Step 6 — Deploy Demo Apps](#step-6--deploy-demo-apps)
- [Step 7 — Check Status](#step-7--check-status)
- [Step 8 — Sync Applications](#step-8--sync-applications)
- [Step 9 — Verify Workloads](#step-9--verify-workloads)
- [Phase 4 — HA Ingress & DNS](#phase-4--ha-ingress--dns)
- [Troubleshooting](#troubleshooting)
- [Known Issues](#known-issues)
- [Uninstall](#uninstall)
- [Directory Structure](#directory-structure)

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| `kubectl` | Cluster management | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| Kubernetes v1.32+ | Target cluster | DigitalOcean (3 CP + 3 W), k3s |
| `argocd` CLI | App management | [argoproj.github.io/argo-cd/cli_installation](https://argo-cd.readthedocs.io/en/stable/cli_installation/) |
| GitLab PAT | Repo authentication | GitLab → Settings → Access Tokens |

## Step 0 — Verify Prerequisites

```bash
# Check kubectl can reach cluster
kubectl version --client --short 2>/dev/null || kubectl version --client
kubectl cluster-info

# Check argocd CLI
argocd version --client

# Verify cluster version >= 1.30
kubectl version --output jsonpath='{.serverVersion.gitVersion}'
```

## Step 1 — Install ArgoCD

### Option A: One-command install (recommended)

```bash
chmod +x bootstrap/install.sh
./bootstrap/install.sh
```

The script:
- Creates the `argocd` namespace
- Applies the v2.14.0 install manifest
- Waits for core deployments to be ready
- Prints admin credentials and next steps

Customize version:
```bash
ARGOCD_VERSION=v2.13.0 ./bootstrap/install.sh
```

### Option B: Manual install

```bash
kubectl apply -f bootstrap/namespace.yaml
kubectl apply -f bootstrap/install.yaml -n argocd

# Wait for pods
kubectl get pods -n argocd -w
```

## Step 2 — Access Dashboard

```bash
# Port-forward the API server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# In another terminal — get initial admin password
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d && echo
```

Open **https://localhost:8080** and login:

| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | *(output of command above)* |

> **Note:** Browser will show a self-signed certificate warning. Click through it.

## Step 3 — Login via CLI

```bash
# Get password
PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d)

# Login (while port-forward is running)
argocd login localhost:8080 --username admin --password "${PASSWORD}" --insecure
```

Verify:
```bash
argocd account list
```

## Step 4 — Connect GitLab Repo

### Option A: Via argocd CLI

```bash
argocd repo add https://github.com/Wsangsrichan/gitops-argocd.git \
  --username <gitlab-username> \
  --password <gitlab-pat>
```

### Option B: Via kubectl (Secret)

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  url: https://github.com
  username: <gitlab-username>
  password: <gitlab-pat>
EOF
```

> **Important:** The GitLab PAT is NOT stored in Git. Apply it manually via kubectl.
> This secret is gitignored.

### Verify repo connection

```bash
# Via CLI
argocd repo list

# Via UI: Settings → Repositories — should show "Successful"
```

## Step 5 — Create AppProject

```bash
kubectl apply -f projects/demo-project.yaml
```

Verify:
```bash
argocd proj list
```

The `demo-project` allows deploying to `guestbook` and `nginx-demo` namespaces only.

## Step 6 — Deploy Demo Apps

### Option A: App of Apps (recommended)

Deploys all child applications through a single parent:

```bash
kubectl apply -f argocd/root-app.yaml
```

### Option B: Individual applications

```bash
kubectl apply -f apps/guestbook/Application.yaml
kubectl apply -f apps/nginx-demo/Application.yaml
```

## Step 7 — Check Status

```bash
# List all apps
argocd app list

# Detailed status per app
argocd app get guestbook
argocd app get nginx-demo

# Check ArgoCD pods
kubectl get pods -n argocd
```

Expected: Apps show `Sync Status: OutOfSync` and `Health Status: Missing` — this is normal
before first sync.

## Step 8 — Sync Applications

### Sync all via parent app

```bash
argocd app sync root-app --cascade
```

### Sync individual apps

```bash
argocd app sync guestbook
argocd app sync nginx-demo
```

### Via UI

Open the dashboard, click **Sync** on each application.

## Step 9 — Verify Workloads

```bash
# Check deployed pods
kubectl get pods -n guestbook
kubectl get pods -n nginx-demo

# Port-forward demo apps
kubectl port-forward svc/guestbook -n guestbook 8081:80
kubectl port-forward svc/nginx-demo -n nginx-demo 8082:80
```

- **Guestbook:** http://localhost:8081
- **Nginx Demo:** http://localhost:8082

ArgoCD dashboard should show all apps `Synced` and `Healthy`.

## Phase 4 — HA Ingress & DNS

Production deployment on DigitalOcean 6-node cluster with `*.ipptt.com` ingress.

| Service | URL | Auth |
|---------|-----|------|
| ArgoCD (HA) | https://argocd.ipptt.com | admin |
| Guestbook | https://guestbook.ipptt.com | — |
| Nginx Demo | https://nginx.ipptt.com | — |
| Grafana | https://grafana.ipptt.com | admin/admin |

**ArgoCD HA Mode** — 8 pods, Redis HA (sentinel-based failover):
```
argocd-server → argocd-redis-ha-haproxy:26379 → argocd-redis-ha-server:6379
```

## Troubleshooting

### Pods stuck in Pending/ContainerCreating

```bash
# Check events
kubectl describe pod <pod-name> -n argocd

# Common causes:
# - Insufficient resources: kubectl describe nodes
# - Image pull issues: kubectl logs <pod-name> -n argocd
# - PVC issues: kubectl get pvc -n argocd
```

### Repo connection fails

```bash
# Test connectivity from cluster
kubectl run tmp --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s -o /dev/null -w "%{http_code}" https://github.com/Wsangsrichan/gitops-argocd.git

# Verify secret exists
kubectl get secret gitlab-repo-creds -n argocd -o yaml

# Re-add repo with correct PAT
argocd repo add https://github.com/Wsangsrichan/gitops-argocd.git \
  --username <user> --password <pat> --upsert
```

### Application stuck OutOfSync

```bash
# Check diff
argocd app diff <app-name>

# Force hard refresh
argocd app get <app-name> --hard-refresh

# Check for resource conflicts
kubectl get all -n <target-namespace>
```

### Reset admin password

```bash
# Generate new password
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {"admin.password": "'"$(htpasswd -nbBC 10 admin NEW_PASSWORD | tr -d ':\n' | sed 's/$2y/$2a/')"'"}}'

# Or reset to random (then grab from secret)
argocd account update-password --account admin --current-password <current> --new-password <new>
```

## Known Issues

| Issue | Workaround | Fix |
|-------|-----------|-----|
| Inter-node DNS blocked (port 53) | CoreDNS=1 + ArgoCD pinned to controlplan-0 | Open UDP/TCP 53 on DO firewall |
| HA replicas scaled to 1 | Pod anti-affinity + single-node limit | Scale after DNS fix |
| Grafana datasource manual | Connect Prometheus at `http://prometheus-server.monitoring.svc.cluster.local` | Provision via ConfigMap |

## Uninstall

```bash
chmod +x bootstrap/uninstall.sh
./bootstrap/uninstall.sh
```

The script prompts for confirmation, then removes:
1. Application and AppProject resources
2. GitLab repo credential secrets
3. ArgoCD install manifest
4. The `argocd` namespace

To also remove cluster-scoped CRDs:
```bash
kubectl delete crd applications.argoproj.io appprojects.argoproj.io
```

## Directory Structure

```
gitops-argocd/
├── bootstrap/
│   ├── install.sh           # Automated install script
│   ├── uninstall.sh         # Automated uninstall script
│   ├── namespace.yaml       # argocd namespace
│   └── install.yaml         # ArgoCD v2.14 core manifest
├── projects/
│   └── demo-project.yaml    # RBAC-bounded demo project
├── apps/
│   ├── guestbook/            # Helm-based demo
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── templates/
│   │   └── Application.yaml
│   └── nginx-demo/          # Kustomize-based demo
│       ├── base/
│       └── Application.yaml
│   ├── ingress/                # NGINX Ingress rules (*.ipptt.com)
│   │   ├── argocd.yaml         # argocd.ipptt.com → ArgoCD UI
│   │   ├── guestbook.yaml      # guestbook.ipptt.com → Guestbook
│   │   ├── nginx-demo.yaml     # nginx.ipptt.com → Nginx Demo
│   │   └── grafana.yaml        # grafana.ipptt.com → Grafana
│   ├── monitoring/             # Prometheus + Grafana stack
│   └── quotas/                 # ResourceQuota enforcement
├── .planning/                  # GSD planning documents
│   └── phases/
│       ├── 02-deploy/
│       ├── 03-ingress-monitoring/
│       └── 04-production-deploy/
└── argocd/
    └── root-app.yaml           # App of Apps (HA ArgoCD, Auto-Sync)
```

## Sync Policy

ArgoCD HA (v2.14) with **auto-sync enabled** — `automated.prune: true`, `automated.selfHeal: true`. Apps sync automatically from GitHub on every push.

## Phase History
| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Bootstrap ArgoCD core | ✅ |
| Phase 2 | AppProjects + demo apps | ✅ |
| Phase 2b | SealedSecrets + Auto-Sync | ✅ |
| Phase 3 | Ingress + Monitoring + Quotas | ✅ |
| Phase 4 | HA redeploy (6-node DO, ipptt.com, Redis HA) | ✅ |

## License

Internal use — Haocomm
