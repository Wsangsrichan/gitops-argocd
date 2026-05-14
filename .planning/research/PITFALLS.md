# Common ArgoCD Pitfalls & Gotchas

> Hard-won lessons from the community and official documentation.  
> Target: First-time ArgoCD setup on Kubernetes v1.30 with GitLab.

---

## 1. Secret Management: The #1 Pitfall

### The Problem

ArgoCD stores all configuration (Applications, AppProjects, repos) as Kubernetes resources. **Kubernetes Secrets are only base64-encoded, not encrypted.** You cannot safely commit them to Git.

### Solutions (Ranked by Complexity)

| Solution | How It Works | GitOps-Friendly? | Complexity |
|----------|-------------|-----------------|------------|
| **SealedSecrets** (Bitnami) | Encrypts Secrets into a SealedSecret CRD that IS safe to commit. Controller decrypts in cluster. | ✅ Yes | Low |
| **External Secrets Operator** | Syncs secrets from external providers (Vault, AWS Secrets Manager, GCP Secret Manager, GitLab Variables) into K8s Secrets. | ✅ Yes | Medium |
| **SOPS + Age/GPG** | Encrypts Secret values in YAML files. ArgoCD can decrypt on-the-fly (requires CMP or Kustomize plugin). | ✅ Yes | Medium |
| **Vault + CMP** | ArgoCD plugin fetches secrets from HashiCorp Vault at render time. | ✅ Yes | High |
| **Manual apply** | `kubectl apply -f secret.yaml` outside of Git. | ❌ No | Low |
| **argocd-vault-plugin** | Sidecar CMP that replaces placeholders with Vault values during manifest generation. | ✅ Yes | Medium |

### Recommendation for Phase 1

**Use kubectl to manually apply two secrets** (not stored in Git):
1. GitLab PAT for repository access (`repo-creds` Secret).
2. argocd-secret (contains admin password hash — managed by ArgoCD itself).

**For Phase 2:** Migrate to **SealedSecrets** — it's the simplest GitOps-native approach and widely used in the ArgoCD community.

### SealedSecrets Setup (Future)

```bash
# Install controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml

# Seal a secret
kubectl create secret generic gitlab-repo-creds \
  --from-literal=username=gitlab-ci-token \
  --from-literal=password=glpat-xxxx \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > gitlab-repo-creds-sealed.yaml

# The sealed file IS safe to commit to Git.
```

> ⚠️ **SealedSecrets gotcha**: The `kubeseal` command strips labels from the original Secret. You MUST re-add the `argocd.argoproj.io/secret-type: repo-creds` label after sealing, or ArgoCD won't recognize the secret.

---

## 2. Sync Waves: Ordering Resources

### The Problem

ArgoCD applies resources in parallel by default. If a Deployment depends on a CRD, or a workload depends on a ConfigMap, you need ordering.

### Solution: Sync Wave Annotations

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"   # CRDs first
---
annotations:
    argocd.argoproj.io/sync-wave: "0"    # ConfigMaps/Secrets (default)
---
annotations:
    argocd.argoproj.io/sync-wave: "2"    # Deployments/StatefulSets
---
annotations:
    argocd.argoproj.io/sync-wave: "5"    # Post-deploy Jobs/Hooks
```

**Rules:**
- Lower numbers sync first.
- Resources within the same wave sync in parallel.
- ArgoCD waits for a wave to be healthy before starting the next wave.

### Gotcha: Wave vs Hook

- **Sync waves** control ordering of standard resources (Deployments, Services, etc.).
- **Sync hooks** are for ephemeral Jobs/Pods that run at specific lifecycle points (PreSync, Sync, PostSync, SyncFail).
- Don't use hooks for resources that should persist after sync.

---

## 3. Health Checks: Custom Resources

### The Problem

ArgoCD has built-in health checks for standard K8s resources (Deployment, Service, etc.), but **Custom Resources (CRDs)** have no health logic by default. They show as "Healthy" immediately after creation, even if the underlying operator hasn't finished reconciling.

### Solution: Custom Health Checks in argocd-cm

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
data:
  resource.customizations.health.cert-manager.io/Certificate: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.conditions ~= nil then
        for i, condition in ipairs(obj.status.conditions) do
          if condition.type == "Ready" and condition.status == "True" then
            hs.status = "Healthy"
            hs.message = condition.message
            return hs
          end
        end
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for certificate"
    return hs
```

This uses Lua scripts to evaluate CRD status. See the [ArgoCD Resource Health docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/) for the full Lua DSL.

---

## 4. Resource Pruning: The Nuclear Option

### The Problem

When `automated.prune: true`, ArgoCD will **delete any cluster resource** that exists in the cluster but is NOT defined in Git. This includes manually created resources, or resources that someone removed from Git.

### Prevention Strategies

1. **Use `PruneLast: true`** sync option — prunes old resources only after new ones are healthy.
2. **Use `prune: false`** in production sync policies — manually verify diffs before pruning.
3. **Use `syncOptions: PrunePropagationPolicy=foreground`** — ensures dependent resources are cleaned up first.
4. **Never set `automated.prune: true`** on namespaces that contain manually-managed resources.

### The `resources-finalizer` Gotcha

Without the `resources-finalizer.argocd.argoproj.io` finalizer on an Application, **deleting the Application does NOT delete the deployed resources**. They become orphaned. Always include this finalizer unless you explicitly want orphaned resources:

```yaml
metadata:
  finalizers:
    - resources-finalizer.argocd.argoproj.io
```

---

## 5. Repository Credentials Setup

### Pitfall 1: URL Pattern Mismatch

**Repo-creds** (credential templates) match repositories by URL prefix. If your GitLab URL doesn't match, ArgoCD silently ignores the credential and the repo clone fails.

```yaml
# This matches ALL repos under gitlab.example.com
url: https://gitlab.example.com

# This matches only repos under a specific group
url: https://gitlab.example.com/team
```

Always verify: `argocd repo list` to confirm the repo is connected with correct credentials.

### Pitfall 2: GitLab `.git` Suffix

**GitLab sometimes redirects `https://gitlab.example.com/group/repo` to `https://gitlab.example.com/group/repo.git`.** ArgoCD does NOT follow HTTP 301/302 redirects for Git operations. Always add `.git` to GitLab repository URLs:

```
✅ https://gitlab.example.com/team/gitops-argocd.git
❌ https://gitlab.example.com/team/gitops-argocd
```

### Pitfall 3: Self-Signed TLS on GitLab

If your GitLab uses a self-signed or internal CA certificate, ArgoCD needs that CA in its trust store. Add it to `argocd-tls-certs-cm`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-tls-certs-cm
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
data:
  gitlab.example.com: |
    -----BEGIN CERTIFICATE-----
    ... (your CA certificate) ...
    -----END CERTIFICATE-----
```

---

## 6. App of Apps vs Single Apps

### App of Apps Pattern

A parent Application creates child Applications, which deploy actual resources.

**Pros:**
- Single bootstrap point: apply one root Application, get everything.
- Enables ArgoCD to manage ArgoCD (self-management).
- Logical grouping: all project apps managed by one root.

**Cons:**
- If the root app breaks, all child apps are orphaned (not deleted, but no longer synced).
- Requires understanding of the indirection.
- Harder to debug: "why is my Deployment not syncing?" → trace through 2+ Application layers.

### Recommendation

Use App of Apps for **cluster bootstrapping** (infrastructure, shared services). Use **direct Applications** for workload apps.

```
Root App (App of Apps)
├── App: cluster-config (CRDs, RBAC, namespaces)
├── App: monitoring (Prometheus/Grafana)
├── App: ingress (nginx-ingress)
└── App: cert-manager

Direct Apps (NOT nested)
├── App: guestbook
└── App: nginx-demo
```

This avoids deep nesting while still getting the bootstrap benefits.

---

## 7. Self-Heal vs Drift Detection

### The Behavior

| Setting | Behavior |
|---------|----------|
| `automated.selfHeal: false` (default) | ArgoCD detects drift (shows OutOfSync) but does NOT auto-correct. Requires manual sync. |
| `automated.selfHeal: true` | ArgoCD auto-corrects ANY drift. If someone runs `kubectl edit deployment`, ArgoCD reverts it within seconds. |

### The Pitfall

`selfHeal: true` means you can NEVER manually patch resources and have the changes stick. This is the goal of GitOps, but it surprises operators who are used to `kubectl edit`.

**Recommendation:**
- Development/staging: `selfHeal: true` (full GitOps).
- Production: `selfHeal: false` initially. Monitor drift and sync deliberately.

---

## 8. ConfigMap/Secret Label Requirement

ArgoCD uses a label selector to find its configuration ConfigMaps and Secrets. **If you forget the label, ArgoCD silently ignores your config.**

```yaml
metadata:
  labels:
    app.kubernetes.io/part-of: argocd    # ← REQUIRED
```

Without this label on `argocd-cm`, `argocd-rbac-cm`, `argocd-tls-certs-cm`, etc., ArgoCD will not read your configuration changes.

---

## 9. Application Names Are Unique (Global Scope)

Application names are globally unique within an ArgoCD instance — not scoped by project. Two different projects cannot have an Application named `guestbook`. Use naming conventions:

```
✅ demo-guestbook, team-a-guestbook, team-b-guestbook
❌ guestbook (in multiple projects)
```

---

## 10. Resource Exclusion/Inclusion in Projects

AppProject `namespaceResourceWhitelist` and `namespaceResourceBlacklist` are **mutually exclusive**. If you define a whitelist, any resource NOT in the whitelist is denied — the blacklist is ignored.

**Rule of thumb:** Use whitelist when you want an explicit allowlist. Use blacklist when you want to allow everything except a few dangerous resources.

```yaml
# This ALLOWS only Deployment and Service. Everything else (including ConfigMap, Secret) is DENIED.
namespaceResourceWhitelist:
  - group: 'apps'
    kind: Deployment
  - group: ''
    kind: Service

# This DENIES only NetworkPolicy. Everything else is ALLOWED.
namespaceResourceBlacklist:
  - group: 'networking.k8s.io'
    kind: NetworkPolicy
```

---

## 11. The `argocd` Namespace Is Special

Applications and AppProjects MUST live in the same namespace where ArgoCD is installed (default: `argocd`). If you deploy them to a different namespace, ArgoCD won't see them (unless you configure Application-in-any-namespace).

**ArgoCD v2.8+** supports "Applications in any namespace" (`--application-namespaces` flag), but this adds complexity. Stick with the `argocd` namespace for Phase 1.

---

## 12. Ignoring Differences (Managed Fields)

Kubernetes mutates resources after they're applied (e.g., adding default values, mutating webhooks injecting sidecars, HPA scaling the replica count). These cause perpetual `OutOfSync` unless ignored:

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas           # Ignore HPA-managed replicas
        - /spec/template/metadata/annotations/rollme  # Ignore CI rollout annotations
    - group: ''
      kind: Service
      jsonPointers:
        - /spec/clusterIP           # Auto-assigned by K8s
        - /spec/clusterIPs
```

---

## Quick Checklist for First-Time Setup

- [ ] GitLab PAT has `read_repository` scope (minimum needed).
- [ ] Repository URL includes `.git` suffix for GitLab.
- [ ] `argocd.argoproj.io/secret-type: repo-creds` label on credential secret.
- [ ] `app.kubernetes.io/part-of: argocd` label on all ConfigMaps.
- [ ] Application YAML includes `resources-finalizer.argocd.argoproj.io`.
- [ ] AppProject `destinations` does NOT include the `argocd` namespace (unless admin project).
- [ ] `CreateNamespace=true` in syncOptions if target namespace doesn't exist yet.
- [ ] Self-signed GitLab CA added to `argocd-tls-certs-cm`.
- [ ] `automated.prune` is `false` for production.
- [ ] Application names are globally unique.
- [ ] Tests: `argocd repo list` and `argocd app get guestbook` work.
