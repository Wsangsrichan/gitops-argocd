# Technology Stack Comparison & Version Matrix

> Research source: https://argo-cd.readthedocs.io/en/stable/  
> Target: Kubernetes v1.30 + GitLab source control

---

## Comparison: ArgoCD vs FluxCD vs Manual kubectl

| Criteria | ArgoCD | FluxCD | Manual kubectl / CI Pipeline |
|----------|--------|--------|------------------------------|
| **GitOps model** | Pull (agent in cluster) | Pull (agent in cluster) | Push (CI pushes changes) |
| **API/UI** | Rich Web UI + gRPC/REST API + CLI | CLI-focused, optional Web UI (Flux UI) | None (kubectl) |
| **Multi-tenancy** | AppProjects with RBAC, source repo allowlists, destination restrictions | Tenant-based via namespaces + RBAC | None (manual enforcement) |
| **Sync strategies** | Auto-sync + prune + selfHeal, sync waves, hooks, progressive syncs | Auto-reconciliation, dependsOn ordering, health checks | Manual, error-prone |
| **Config tools** | Helm, Kustomize, plain YAML, CMP plugins | Helm, Kustomize, plain YAML, OCIRepository | Manual |
| **Drift detection** | Built-in, visual diff in UI | Built-in, reports drift | None |
| **Rollback** | One-click rollback in UI/CLI | Flux's HelmRelease supports rollback | Manual |
| **Multi-cluster** | First-class; single ArgoCD can manage many clusters | Separate Flux install per cluster (or remote apply) | Manual |
| **Bootstrapping** | App of Apps pattern, cluster bootstrapping docs | `flux bootstrap` command | Manual |
| **Complexity** | Medium (3 services + Redis) | Lower (single binary/controller) | Low (but high human overhead) |
| **CNCF status** | Graduated | Graduated | N/A |
| **GitLab integration** | Webhook + PAT/SSH, API-driven | Webhook + PAT/SSH, SOPS for secrets | Manual PAT in CI |

### Why ArgoCD for This Project

1. **Multi-tenancy with RBAC**: AppProjects provide fine-grained control over which repos and namespaces applications can use — essential for a GitLab-connected multi-team setup.
2. **Rich Web UI**: Non-Kubernetes-experts can see sync status, diff manifests, and roll back via UI. GitLab's CI/CD users benefit from visual feedback.
3. **ApplicationSet controller** (included): Automatically generate Applications from Git directories, clusters, or GitLab SCM providers — enables self-service.
4. **Progressive sync & sync waves**: Control deployment ordering for complex stacks.
5. **Mature ecosystem**: Largest GitOps community, extensive integrations, and enterprise adoption.

### When FluxCD Might Be Preferable

- Simpler architecture desired (fewer components to maintain).
- Heavy Terraform/Tofu usage (Flux's OCIRepository + SOPS is tight with infra-as-code).
- Simpler single-cluster, single-team use case.

---

## ArgoCD Version Matrix (Kubernetes v1.30)

Based on official ArgoCD tested-versions documentation:

| ArgoCD Version | Explicitly Tested K8s Versions | Notes |
|---------------|-------------------------------|-------|
| **v3.0** | v1.32, v1.31, v1.30, v1.29 | Latest major that tests k8s 1.30; API breaking changes from 2.x |
| **v2.14** | v1.31, v1.30, v1.29, v1.28 | Final 2.x feature release; most stable for k8s 1.30 |
| **v2.13** | v1.30, v1.29, v1.28, v1.27 | Older, approaching EOL |
| v3.1+ | v1.34, v1.33, v1.32, v1.31 | Drops testing on k8s 1.30 |
| v3.2+ | v1.35, v1.34, v1.33, v1.32 | Drops testing on k8s 1.30 |

### Recommendation: **ArgoCD v2.14** for initial deployment

**Rationale:**
- Explicitly tested against Kubernetes v1.30.
- Mature 2.x codebase with extensive community battle-testing.
- No breaking API changes (v3.0 dropped some v1alpha1 API versions).
- Clear upgrade path to v3.0+ later when we move to newer Kubernetes.

If you want the latest features and are willing to handle the 2.x→3.0 migration later, v3.0 also explicitly tests k8s 1.30. But v2.14 is the safest choice for a first-time setup.

---

## GitLab Integration Notes

### Authentication: Personal Access Token (PAT)

GitLab repositories are always private in practice. ArgoCD needs read access to clone and pull.

**Recommended approach:** Create a GitLab project access token with `read_repository` scope (minimum permission). Store it as a Kubernetes Secret:

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
  username: gitlab-ci-token   # or your service account username
  password: glpat-xxxxxxxxxx  # GitLab Personal Access Token
```

Using `secret-type: repo-creds` (credential template) allows the same credentials to be shared across all repositories matching the URL prefix.

**GitLab URL gotcha:** Some GitLab instances require `.git` suffix on repository URLs. Always test with `https://gitlab.example.com/group/repo.git`.

### Webhook vs Polling

| Method | How It Works | Pros | Cons |
|--------|-------------|------|------|
| **Polling** (default) | ArgoCD polls Git every 3 minutes (configurable via `timeout.reconciliation`). Compares latest commit SHA. | Simple, no extra setup. Works with any Git server. | Up to 3-minute delay; adds load at scale. |
| **Webhook** | GitLab sends HTTP POST to ArgoCD API server on push events. ArgoCD immediately triggers reconciliation. | Near-instant sync trigger. Efficient at scale. | Requires network path from GitLab to ArgoCD API server; webhook secret management. |

**For this project:** Start with polling (no extra configuration), add webhooks later if faster sync is needed.

**Webhook setup (future):**
1. Generate a webhook secret and store it in `argocd-secret`.
2. Configure ArgoCD API server ingress/TLS.
3. Register the webhook URL in GitLab: `https://argocd.example.com/api/webhook`.
4. Select "Push events" trigger.

---

## Component Version Summary

| Component | Version | Notes |
|-----------|---------|-------|
| Kubernetes | **v1.30** | Target cluster |
| ArgoCD | **v2.14.x** | Recommended for k8s 1.30 |
| GitLab | Self-managed or gitlab.com | Requires PAT with `read_repository` |
| Container Registry | Any OCI-compatible | For demo app images |

---

## Key Dependencies

- **Redis**: Used by ArgoCD for caching (included in install manifests).
- **argocd CLI**: Recommended for debugging and automation (can be installed via Homebrew, direct download, or `kubectl` plugin).
- **Dex** (optional): Only needed for SSO/OIDC integration. Not required for local admin user.
