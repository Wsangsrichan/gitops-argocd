# Project Feature Scope

> What we are building: ArgoCD GitOps pipeline for Kubernetes v1.30 with GitLab source control.

---

## Phase 1: Bootstrap ArgoCD

### 1.1 Install ArgoCD on Kubernetes v1.30

**Method: `kubectl apply` + Kustomize (recommended declarative approach)**

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD v2.14 (stable manifests)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.0/manifests/install.yaml
```

Alternatively, use a local `kustomization.yaml` for repeatable, GitOps-managed installation:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
  - https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.0/manifests/install.yaml
patches:
  - patch: |-
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: argocd-cm
      data:
        timeout.reconciliation: 180s
```

### 1.2 Expose ArgoCD API Server

Options (in priority order):
1. **Ingress + TLS** (recommended for production): Configure an Ingress resource with cert-manager for TLS.
2. **LoadBalancer Service**: `kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'`
3. **Port-forward** (dev only): `kubectl port-forward svc/argocd-server -n argocd 8080:443`

### 1.3 Get Initial Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 1.4 Install ArgoCD CLI (Optional but Recommended)

```bash
brew install argocd        # macOS
# or
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
```

Login: `argocd login <SERVER> --username admin --password <PASSWORD>`

---

## Phase 2: Connect GitLab Repository

### 2.1 Create GitLab Repository Structure

Our GitLab repository will follow the standard GitOps layout (see ARCHITECTURE.md for full tree):

```
gitlab.example.com/team/gitops-argocd.git/
├── apps/                    # Application definitions
│   ├── guestbook/
│   │   ├── Chart.yaml       # If using Helm
│   │   ├── values.yaml
│   │   └── templates/
│   └── nginx-demo/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── kustomization.yaml
├── projects/                # AppProject definitions
│   └── demo-project.yaml
└── argocd/                  # Root "app of apps" definition
    └── root-app.yaml
```

### 2.2 Configure Repository Credentials in ArgoCD

Create a Kubernetes Secret containing the GitLab PAT:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  type: git
  url: https://gitlab.example.com
  username: gitlab-ci-token
  password: glpat-xxxxxxxxxxxxxxxxxxxx
```

> **SECURITY**: Never commit this secret to Git. Use SealedSecrets or External Secrets Operator for GitOps-friendly secret management. See PITFALLS.md.

Apply: `kubectl apply -f repo-creds-secret.yaml`

### 2.3 (Optional) Configure GitLab Webhook

For faster sync than polling:
1. Store webhook secret in `argocd-secret` (`server.webhook.github.secret` key).
2. Register webhook URL in GitLab: `https://argocd.example.com/api/webhook`.
3. Select "Push events" trigger.

---

## Phase 3: Create Example AppProject (with RBAC/Restrictions)

### 3.1 AppProject Definition

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: demo
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: Demo project for evaluating ArgoCD GitOps

  # Restrict which Git repositories can be used
  sourceRepos:
    - https://gitlab.example.com/team/gitops-argocd.git

  # Restrict which clusters/namespaces can be deployed to
  destinations:
    - namespace: guestbook
      server: https://kubernetes.default.svc
    - namespace: nginx-demo
      server: https://kubernetes.default.svc

  # Allow only specific namespaced resources (least privilege)
  namespaceResourceWhitelist:
    - group: ''
      kind: ConfigMap
    - group: ''
      kind: Secret
    - group: ''
      kind: Service
    - group: 'apps'
      kind: Deployment
    - group: 'apps'
      kind: StatefulSet
    - group: 'networking.k8s.io'
      kind: Ingress
    - group: 'batch'
      kind: Job
    - group: 'batch'
      kind: CronJob

  # Allow Namespace creation at cluster scope
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace

  # Explicitly deny dangerous resources
  namespaceResourceBlacklist:
    - group: ''
      kind: ResourceQuota
    - group: ''
      kind: LimitRange

  # Roles for CI/CD automation
  roles:
    - name: ci-syncer
      description: CI role that can sync applications in this project
      policies:
        - p, proj:demo:ci-syncer, applications, sync, demo/*, allow
```

**RBAC explained:**
- The `ci-syncer` role can trigger sync for any app in the `demo` project.
- JWT tokens can be generated for this role and used in GitLab CI pipelines.
- The `sourceRepos` restricts apps in this project to only use our specific GitLab repo.
- The `destinations` restricts apps to only deploy to `guestbook` and `nginx-demo` namespaces.

---

## Phase 4: Create Example Applications

### 4.1 Guestbook Application (Helm-based)

This uses the classic ArgoCD example app (guestbook) as a Helm chart:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: demo
  source:
    repoURL: https://gitlab.example.com/team/gitops-argocd.git
    targetRevision: main
    path: apps/guestbook
    helm:
      values: |
        service:
          type: ClusterIP
        replicaCount: 2
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 4.2 Nginx Demo Application (Plain YAML/Kustomize)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-demo
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: demo
  source:
    repoURL: https://gitlab.example.com/team/gitops-argocd.git
    targetRevision: main
    path: apps/nginx-demo
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx-demo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## Phase 5: Sync Policies & Health Monitoring

### 5.1 Sync Policy Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| **Manual** (default) | User clicks "Sync" in UI or runs `argocd app sync`. | Production with change control. |
| **Automated (no prune)** | Auto-syncs on Git change. Does NOT delete resources removed from Git. | Staging, cautious teams. |
| **Automated + prune** | Auto-syncs + deletes resources removed from Git. | Dev/test environments. |
| **Automated + selfHeal** | Auto-syncs + auto-corrects drift even without a Git commit. | Full GitOps enforcement. |

For this project:
- **Dev/Staging**: Automated + prune + selfHeal
- **Production** (future): Manual sync with GitLab CI triggering sync via JWT token

### 5.2 Sync Options

| Option | Effect |
|--------|--------|
| `CreateNamespace=true` | Auto-create the target namespace if it doesn't exist. |
| `PruneLast=true` | Prune resources only after new ones are healthy (safer for Deployments). |
| `ApplyOutOfSyncOnly=true` | Only apply resources that are OutOfSync (faster syncs). |
| `Validate=false` | Skip `kubectl` dry-run validation (useful for CRDs applied in same sync). |
| `RespectIgnoreDifferences=true` | Respect configured ignoreDifferences during sync. |

### 5.3 Sync Waves (Ordering)

Use the `argocd.argoproj.io/sync-wave` annotation to control deployment order:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"   # Runs first (e.g., CRDs)
---
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"    # Default
---
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "5"    # Runs last (e.g., canary checks)
```

Waves execute from lowest to highest number. Within a wave, resources sync in parallel.

### 5.4 Sync Hooks

Execute Kubernetes Jobs/Pods at specific lifecycle points:
- **PreSync**: Before the sync (e.g., database migrations, schema updates).
- **Sync**: As part of the sync wave (replace the normal apply behavior).
- **PostSync**: After the sync completes (e.g., smoke tests, notifications).
- **SyncFail**: On sync failure (e.g., cleanup, alerting).

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

### 5.5 Health Monitoring

ArgoCD provides built-in health checks for common resources:
- **Deployment/StatefulSet/DaemonSet**: Healthy when `readyReplicas == desiredReplicas`.
- **Service**: Always healthy (just exists).
- **Ingress**: Healthy when load balancer status is populated.
- **Job**: Healthy when completed successfully.
- **PVC**: Healthy when bound.

Custom health checks can be defined in `argocd-cm` ConfigMap for CRDs.

### 5.6 Notifications (Future)

ArgoCD Notifications (bundled as separate controller) can send alerts to:
- Slack, Microsoft Teams, Telegram, Email, PagerDuty, Opsgenie
- Webhooks (generic)
- GitLab commit status updates

---

## What We Are NOT Building (Phase 1)

- **SSO/OIDC integration** (Dex + Keycloak/Auth0/Okta) — local admin user suffices for initial setup.
- **SealedSecrets / External Secrets Operator** — documented in PITFALLS.md, but initial setup uses direct Kubernetes Secrets.
- **ApplicationSet controller** — will use manual Application CRDs; ApplicationSets are a natural next step.
- **HA deployment** — single replicas for initial setup; add HA later.
- **Multi-cluster management** — single cluster only.
