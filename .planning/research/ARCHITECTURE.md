# Architecture & Directory Layout

> ArgoCD GitOps architecture for Kubernetes v1.30 with GitLab source control.

---

## High-Level Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           DEVELOPER WORKFLOW                            │
│                                                                         │
│  Developer ──git push──▶ GitLab Repository                              │
│                          (gitlab.example.com/team/gitops-argocd.git)    │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │
                                    │ Git doesn't push to cluster.
                                    │ ArgoCD pulls from Git.
                                    │ (GitOps Pull Model)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       ARGOCD (Kubernetes Cluster)                       │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────┐      │
│  │                    argocd-server (API Server)                  │      │
│  │  • Web UI / gRPC-REST API / CLI endpoint                      │      │
│  │  • Authentication (local admin + future SSO)                 │      │
│  │  • RBAC enforcement                                           │      │
│  │  • GitLab webhook receiver (optional)                         │      │
│  └──────────────┬───────────────────────────────┬────────────────┘      │
│                 │                               │                        │
│                 ▼                               ▼                        │
│  ┌─────────────────────────────┐ ┌──────────────────────────────┐      │
│  │  argocd-repo-server          │ │  argocd-application-         │      │
│  │  (Repository Server)         │ │  controller                   │      │
│  │  • Clones Git repos          │ │  • Reconciliation loop        │      │
│  │  • Caches Git repos locally  │ │  • Compares desired vs live   │      │
│  │  • Renders manifests         │ │  • Applies/Prunes resources   │      │
│  │    (Helm, Kustomize, YAML)   │ │  • Executes sync hooks        │      │
│  │  • No K8s RBAC privileges    │ │  • Reports health status      │      │
│  └──────────────┬───────────────┘ └──────────────┬───────────────┘      │
│                 │                                │                       │
│                 │       ┌──────────────┐         │                       │
│                 └──────▶│    Redis     │◀────────┘                       │
│                         │  (Cache)     │                                 │
│                         └──────────────┘                                 │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
                                   │ kubectl apply / prune
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       TARGET NAMESPACES (Same Cluster)                   │
│                                                                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │   guestbook      │  │   nginx-demo    │  │  (future apps)  │         │
│  │  • Deployment    │  │  • Deployment   │  │                 │         │
│  │  • Service       │  │  • Service      │  │                 │         │
│  │  • ConfigMap     │  │  • Ingress      │  │                 │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Component Breakdown

### Core ArgoCD Components (all in `argocd` namespace)

| Component | Image | Role | HA Scaling |
|-----------|-------|------|------------|
| **argocd-server** | `quay.io/argoproj/argocd` | API server: Web UI, gRPC/REST API, auth, RBAC, webhook events | 2+ replicas (active/active) |
| **argocd-repo-server** | `quay.io/argoproj/argocd` | Clones Git repos, renders Helm/Kustomize/YAML manifests | 2+ replicas (stateless, sharded by repo) |
| **argocd-application-controller** | `quay.io/argoproj/argocd` | Reconciliation loop, sync execution, health monitoring | 1 replica only (leader-elected) |
| **argocd-redis** | `redis` | Shared cache for repo server and controller | Sentinel-based HA (3 replicas) |
| **argocd-dex** (optional) | `quay.io/dexidp/dex` | OIDC connector for SSO | Not included in Phase 1 |
| **argocd-notifications** (optional) | `quay.io/argoproj/argocd-notifications` | Event-driven notifications | Not included in Phase 1 |

### Component Communication

```
argocd-server ───gRPC──▶ argocd-repo-server      (manifest generation)
argocd-server ───gRPC──▶ argocd-application-controller  (sync operations)
argocd-application-controller ───gRPC──▶ argocd-repo-server  (manifest comparison)
All components ───TCP──▶ Redis  (state caching)
```

All inter-service communication is TLS-encrypted. Communication with Redis uses plain TCP by default (TLS configurable).

---

## Namespace Structure

```
Kubernetes Cluster
│
├── argocd/                        ◀── ArgoCD itself
│   ├── argocd-server              (Deployment)
│   ├── argocd-repo-server         (Deployment)
│   ├── argocd-application-controller (StatefulSet)
│   ├── argocd-redis               (Deployment)
│   ├── argocd-secret              (admin password, signing key)
│   ├── argocd-cm                  (general config)
│   ├── argocd-rbac-cm             (RBAC policies)
│   ├── argocd-cmd-params-cm       (env vars for components)
│   ├── gitlab-repo-creds          (GitLab PAT secret)
│   ├── Application CRDs:
│   │   ├── root-app               (App of Apps root)
│   │   ├── guestbook              (example app)
│   │   └── nginx-demo             (example app)
│   └── AppProject CRDs:
│       └── demo                   (project with RBAC)
│
├── guestbook/                     ◀── Deployed by ArgoCD
│   ├── guestbook-ui Deployment
│   ├── guestbook-ui Service
│   └── guestbook-db (optional)
│
└── nginx-demo/                    ◀── Deployed by ArgoCD
    ├── nginx Deployment
    ├── nginx Service
    └── nginx Ingress (optional)
```

---

## GitOps Repository Directory Layout

This is the layout of our **GitLab repository** that ArgoCD monitors:

```
gitlab.example.com/team/gitops-argocd.git/
│
├── README.md
│
├── argocd/                              # ArgoCD bootstrap (App of Apps)
│   └── root-app.yaml                    # Parent Application pointing to apps/
│
├── projects/                            # AppProject definitions
│   └── demo-project.yaml                # RBAC-bounded project
│
├── apps/                                # All workload Applications
│   │
│   ├── guestbook/                       # Helm-based app
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── values-staging.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── _helpers.tpl
│   │
│   └── nginx-demo/                      # Kustomize-based app
│       ├── kustomization.yaml
│       ├── base/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   └── kustomization.yaml
│       └── overlays/
│           └── production/
│               ├── kustomization.yaml
│               └── replica-count.yaml
│
├── config/                              # Shared cluster-wide config (future)
│   ├── ingress/
│   ├── monitoring/
│   └── cert-manager/
│
└── docs/                                # Project documentation
    └── architecture.md
```

### Directory Conventions

| Directory | Purpose |
|-----------|---------|
| `argocd/` | The root Application (App of Apps) that bootstraps everything else |
| `projects/` | AppProject CRDs defining RBAC boundaries |
| `apps/` | Individual Application Helm charts / Kustomize overlays |
| `config/` | Cluster-level shared infrastructure (monitoring, ingress, secrets management) |
| `docs/` | Internal documentation |

### The App of Apps Flow

```
root-app.yaml (argocd/root-app.yaml)
    │
    │  source.path: "projects"
    │  → Creates AppProject "demo"
    │
    │  source.path: "apps/guestbook"
    │  → Creates Application "guestbook"
    │      → Deploys to namespace "guestbook"
    │
    │  source.path: "apps/nginx-demo"
    │  → Creates Application "nginx-demo"
    │      → Deploys to namespace "nginx-demo"
```

The root app itself can be created by a bootstrap script or manually via `kubectl apply`. Once created, ArgoCD manages everything else declaratively.

---

## Network & Ports

| Service | Port | Purpose |
|---------|------|---------|
| argocd-server | 443 (HTTPS) | Web UI + API |
| argocd-server | 80 (HTTP, optional) | Redirect to HTTPS |
| argocd-repo-server | 8081 | gRPC (internal only) |
| argocd-application-controller | 8082 | gRPC (internal only) |
| Redis | 6379 | Cache (internal only) |

**Ingress path**: `argocd.example.com → argocd-server:443`

---

## TLS Certificates

| Certificate | Source | Notes |
|-------------|--------|-------|
| ArgoCD API server | Self-signed (default) or cert-manager | Replace with Let's Encrypt via cert-manager |
| Repo-server gRPC | Auto-generated (internal) | Managed by ArgoCD |
| GitLab HTTPS | System trust store | Must trust GitLab's CA if self-signed |
