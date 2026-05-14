# ArgoCD Summary & Key Concepts

> Research source: https://argo-cd.readthedocs.io/en/stable/  
> Target: Kubernetes v1.30 + GitLab source control

---

## What Is ArgoCD?

ArgoCD is a **declarative GitOps continuous delivery tool for Kubernetes**. It is a CNCF-graduated project under the Argo umbrella. Its core philosophy:

1. Application definitions, configurations, and environments should be **declarative and version-controlled**.
2. Application deployment and lifecycle management should be **automated, auditable, and easy to understand**.

ArgoCD runs inside Kubernetes as a set of controllers and services. It continuously monitors Git repositories that define the desired state of applications and reconciles the live cluster state to match.

---

## How GitOps Works with ArgoCD

ArgoCD implements the **pull model** of GitOps:

| Model | Description | ArgoCD's Role |
|-------|-------------|---------------|
| **Push model** | A CI/CD pipeline pushes changes to the cluster (e.g., `kubectl apply`). Cluster credentials live in CI. | ArgoCD does NOT use this. |
| **Pull model** | An agent inside the cluster pulls the desired state from Git and applies it. No external push access needed. | ArgoCD lives inside the cluster and continuously pulls from Git repos. |

### The Reconciliation Loop

```
Git Repo (Desired State) ──pull──▶ ArgoCD ──compare──▶ K8s Cluster (Live State)
                                        │
                                        ▼
                                   OutOfSync? → Auto-Sync / Manual Sync
```

ArgoCD's **application controller** runs a reconciliation loop (default: every 3 minutes) that:
1. Clones/fetches the Git repository.
2. Renders Kubernetes manifests (plain YAML, Helm, Kustomize, or custom plugins).
3. Compares rendered manifests against the live cluster state.
4. Reports sync status: **Synced**, **OutOfSync**, or **Unknown**.
5. Optionally auto-syncs to bring the cluster to the desired state.

---

## Key Concepts

### 1. Application (CRD: `argoproj.io/v1alpha1`)

An **Application** is the core resource. It defines a single deployment unit by specifying:
- **Source**: Git repo URL, revision (commit/branch/tag), path within repo, and config tool (plain YAML, Helm, Kustomize).
- **Destination**: Target cluster (`server` URL or `name`) and namespace.
- **Sync policy**: Manual or automated (auto-prune, self-heal).

**Minimal Application example:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://gitlab.example.com/team/app-config.git
    targetRevision: main
    path: overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Key Application fields:
- `syncPolicy.automated.prune`: Delete cluster resources that are removed from Git.
- `syncPolicy.automated.selfHeal`: Auto-sync when live state drifts from Git (even without a Git commit).
- `syncPolicy.syncOptions`: Fine-grained sync behavior (e.g., `CreateNamespace=true`, `Validate=false`).
- `ignoreDifferences`: Suppress drift detection on specific JSON paths (e.g., fields mutated by admission controllers).
- `finalizers`: The `resources-finalizer.argocd.argoproj.io` enables cascading deletion — deleting the Application also deletes all managed resources.

### 2. AppProject (CRD: `argoproj.io/v1alpha1`)

An **AppProject** is a logical grouping of Applications with RBAC boundaries. It controls:

- **`sourceRepos`**: Which Git repositories Applications in this project may pull from.
- **`destinations`**: Which clusters and namespaces Applications may deploy into.
- **`clusterResourceWhitelist` / `clusterResourceBlacklist`**: Control cluster-scoped resources.
- **`namespaceResourceWhitelist` / `namespaceResourceBlacklist`**: Control namespaced resources.
- **`roles`**: Project-level RBAC with JWT tokens for CI/CD automation.
- **`signatureKeys`**: Enforce GPG signature verification on commits.
- **`orphanedResources`**: Monitor/warn about resources not managed by any Application.

**Security note**: An AppProject that allows deploying to the namespace where ArgoCD is installed (`argocd`) grants admin-level access. Such projects must have tightly restricted push access.

### 3. Repository (Secrets with label `argocd.argoproj.io/secret-type: repository`)

Repository credentials are stored as Kubernetes Secrets in the `argocd` namespace. Supported auth methods:
- **HTTPS**: `username` + `password` (or personal access token for GitLab)
- **SSH**: `sshPrivateKey`
- **GitHub App**: `githubAppID` + `githubAppInstallationID` + `githubAppPrivateKey`
- **Azure Service Principal**
- **Google Cloud Source Repositories**: `gcpServiceAccountKey`

**Repository Credentials** (credential templates): Define a pattern-matching credential that applies to multiple repos matching a URL pattern, rather than a single repo.

> ⚠️ **GitLab note**: GitLab instances may require the `.git` suffix in the repository URL. ArgoCD will NOT follow HTTP 301 redirects. Always use `https://gitlab.example.com/group/repo.git`.

### 4. Cluster

ArgoCD can deploy to:
- The **in-cluster** cluster (where ArgoCD itself runs): `https://kubernetes.default.svc`
- **External clusters**: Added via `argocd cluster add <context>` or declaratively as Secrets.

Cluster credentials are stored as Secrets with label `argocd.argoproj.io/secret-type: cluster`.

---

## Sync Status & Health

| Status | Meaning |
|--------|---------|
| **Synced** | Live state matches desired state in Git. |
| **OutOfSync** | Git has changes not yet applied to the cluster. |
| **Unknown** | ArgoCD cannot determine status (e.g., repo unreachable). |

Health status (separate from sync status):
| Health | Meaning |
|--------|---------|
| **Healthy** | Resource is running correctly (e.g., Deployment has ready replicas). |
| **Progressing** | Resource is in transition (e.g., rollout in progress). |
| **Degraded** | Resource has issues (e.g., CrashLoopBackOff). |
| **Missing** | Resource is defined in Git but not found in the cluster. |

---

## Tooling Support

ArgoCD natively supports three manifest generation tools:
1. **Plain YAML/JSON** — Directories of Kubernetes manifests.
2. **Helm** — Native Helm chart rendering (`helm template` equivalent).
3. **Kustomize** — Built-in Kustomize integration.
4. **Config Management Plugins (CMP)** — Custom plugin system (sidecar container approach in v2.8+) for any manifest tool (Jsonnet, Tanka, etc.).

---

## "App of Apps" Pattern

A foundational pattern where a parent Application deploys child Applications, which in turn deploy actual workloads. This enables **cluster bootstrapping**: install ArgoCD once, then let it manage everything else including its own configuration.

```
Root App ──▶ App A (monitoring)  ──▶ Prometheus, Grafana
        ──▶ App B (ingress)     ──▶ ingress-nginx
        ──▶ App C (guestbook)   ──▶ Deployment, Service, Ingress
```

The root app itself can be managed by ArgoCD (ArgoCD managing ArgoCD). See the `Managed By URL` annotation support.

---

## Key Takeaways for This Project

- We will use the **multi-tenant** installation (standard, not core/headless).
- Repository type: **HTTPS with GitLab Personal Access Token**.
- Sync strategy: **Manual** initially, evolve to **automated with prune and selfHeal**.
- We will use the **App of Apps** pattern for bootstrap and structure.
- All Application and AppProject CRDs must live in the `argocd` namespace.
