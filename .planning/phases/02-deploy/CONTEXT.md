# Phase 2 — Deploy ArgoCD to Kubernetes

## What We Are Deploying

ArgoCD v2.14 (Core/Non-HA) onto a Kubernetes v1.30 cluster using GitOps-managed
manifests stored in this repository. The deployment includes:

- ArgoCD core components (server, repo-server, applicationset-controller, etc.)
- A `demo-project` AppProject scoping deployments to `guestbook` and `nginx-demo` namespaces
- Two demo applications showcasing Helm (guestbook) and Kustomize (nginx-demo) patterns
- An App of Apps pattern (`root-app.yaml`) for managing child applications

## Decision Table

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Install method | `kubectl apply` manifest | No Helm dependency, full control, works on any k8s 1.30+ cluster |
| ArgoCD version | v2.14.0 | Latest stable, tested on k8s 1.30 |
| Install mode | Core (Non-HA) | Single cluster, no HA needed for Phase 1 |
| Dashboard access | port-forward | Simplest, no ingress/LB configuration needed yet |
| Secret management | kubectl manual (Phase 1) | GitLab PAT applied as Secret — not stored in Git |
| Sync policy | Manual | Safety first — no auto-sync or auto-prune in Phase 1 |
| Source control | GitLab | User requirement |
| Demo apps | Guestbook (Helm) + Nginx (Kustomize) | Exercise both source types ArgoCD supports |
| App pattern | App of Apps | `root-app.yaml` manages all child apps via directory recurse |

## Gray Areas (Decisions Needed)

| Area | Status | Notes |
|------|--------|-------|
| Actual GitLab URL | **Placeholder** | `https://gitlab.example.com/team/gitops-argocd.git` — needs real URL |
| Ingress configuration | **Deferred to Phase 3** | Currently using port-forward for dashboard |
| SSO/SAML/OIDC | **Deferred to Phase 3** | Using static admin password in Phase 2 |
| Monitoring/alerting | **Deferred to Phase 3** | No Prometheus rules or Grafana dashboards yet |
| HA mode | **Deferred to Phase 3** | Core mode sufficient for single-cluster dev |
| SealedSecrets | **Deferred to Phase 2b** | GitOps-native secret rotation after initial setup works |
| Namespace quotas | **Deferred to Phase 3** | No resource limits on demo namespaces yet |

## Success Metrics

- [ ] All ArgoCD pods running and healthy in `argocd` namespace
- [ ] ArgoCD API server accessible via port-forward
- [ ] Admin login works (dashboard and CLI)
- [ ] GitLab repo connected — status shows "Successful"
- [ ] `demo-project` AppProject created without errors
- [ ] Both demo apps sync successfully (Synced + Healthy)
- [ ] Guestbook accessible via port-forward on port 8081
- [ ] Nginx-demo accessible via port-forward on port 8082
- [ ] App of Apps pattern works — `root-app` manages child apps

## Files Involved

| File | Role |
|------|------|
| `bootstrap/namespace.yaml` | Creates `argocd` namespace |
| `bootstrap/install.yaml` | ArgoCD v2.14 core manifest (1.3MB, auto-generated) |
| `bootstrap/install.sh` | Automated install with health checks |
| `bootstrap/uninstall.sh` | Clean removal with confirmation |
| `projects/demo-project.yaml` | AppProject scoping to demo namespaces |
| `apps/guestbook/Application.yaml` | Helm-based demo app |
| `apps/nginx-demo/Application.yaml` | Kustomize-based demo app |
| `argocd/root-app.yaml` | App of Apps parent |
