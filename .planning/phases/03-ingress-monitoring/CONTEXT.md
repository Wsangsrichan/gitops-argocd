# Phase 3 — Ingress, Monitoring & Resource Quotas

## What We Are Deploying

Production-grade infrastructure layer on top of the Phase 1–2 GitOps foundation:

- **NGINX Ingress Controller v1.13** — Host-based routing for all cluster services via `ingressClassName: nginx`
- **kube-prometheus-stack** (Helm) — Prometheus for metrics scraping + Grafana for dashboards
- **ResourceQuotas** — CPU/Memory/Pod limits on `guestbook` and `nginx-demo` namespaces

All three sub-phases are deployed on a single-node **kind** cluster (Kubernetes v1.30), which imposes specific constraints on networking and high availability.

## Decision Table

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Ingress controller | NGINX (community) v1.13 | Standard, well-documented, works on kind |
| Ingress exposure on kind | hostPort (80/443) on container + NodePort Service | kind doesn't have a cloud LB; hostPort maps directly to the kind node |
| Node IP for /etc/hosts | `172.19.0.2` (kind container IP) | Auto-detected via `kubectl get node -o jsonpath`; may change on cluster restart |
| Ingress hosts | `argocd.local`, `guestbook.local`, `nginx.local` | Simple local dev domains, no real DNS needed |
| SSL redirect | Disabled (`ssl-redirect: "false"`) | Dev cluster, no TLS certificates; plain HTTP on 80, optional HTTPS on 443 |
| Monitoring install method | Helm v3 (`kube-prometheus-stack`) | Full Prometheus Operator stack with Grafana, Node Exporter, Kube State Metrics |
| Grafana ingress | Enabled (`grafana.local`) | Direct browser access, no port-forward needed |
| Prometheus ingress | Disabled | Internal-only; accessed via port-forward when needed |
| AlertManager | Disabled | Not needed for dev cluster |
| Persistence | Disabled (both Prometheus & Grafana) | Ephemeral dev cluster; data lost on restart is acceptable |
| Prometheus retention | 2 hours | Sufficient for dev debugging |
| Grafana admin credentials | `admin` / `admin` | Default dev credentials; no SSO in Phase 3 |
| ArgoCD dashboard | Grafana ID 14584 | Community dashboard for ArgoCD metrics |
| ServiceMonitor label selector | `release: monitoring` | Standard label used by kube-prometheus-stack Prometheus instance |
| ResourceQuota scope | `guestbook` + `nginx-demo` namespaces | Prevents demo apps from consuming all cluster resources |
| Quota CPU requests | 100m per namespace | Conservative floor for demo workloads |
| Quota CPU limits | 500m per namespace | Sufficient headroom for burst without starving other namespaces |
| Quota memory requests | 128Mi per namespace | Minimum reasonable for any pod |
| Quota memory limits | 512Mi per namespace | Prevents memory exhaustion on single-node kind |
| Quota max pods | 10 per namespace | Prevents pod sprawl in demo namespaces |

## Gray Areas (Decisions Needed)

| Area | Status | Notes |
|------|--------|-------|
| kind node IP | **Dynamic** | `172.19.0.2` can change on cluster restart; `/etc/hosts` must be updated |
| NodePort vs hostPort | **Hybrid on kind** | NGINX controller uses hostPort 80/443 on the container; the Service exposes NodePort 30920/31755. Both work but hostPort is what maps to the kind node. |
| TLS termination | **Skipped** | No cert-manager or self-signed certs in Phase 3; all traffic is HTTP or self-signed HTTPS (controller default) |
| SSO/OIDC for Grafana | **Deferred** | Needs external IdP (Google, GitHub, Okta); `admin/admin` used for dev |
| SSO/OIDC for ArgoCD | **Deferred** | Same as above; static admin password from Phase 2 |
| HA mode | **Skipped** | Single-node kind cannot support HA; one replica of each component |
| Grafana dashboard persistence | **Skipped** | Imported dashboards (ID 14584) lost on restart unless re-imported |
| Alerting rules | **Skipped** | No AlertManager, no notification channels configured |
| Quota for `argocd` namespace | **Skipped** | ArgoCD is infrastructure; no quota applied to avoid disrupting GitOps operations |
| SealedSecrets for Grafana creds | **Skipped** | Admin password in Helm values (plaintext); acceptable for dev, not for prod |

## Success Metrics

- [x] NGINX Ingress Controller running in `ingress-nginx` namespace
- [x] All three Ingress resources created (`argocd`, `guestbook`, `nginx-demo`)
- [x] `/etc/hosts` configured with `172.19.0.2 argocd.local guestbook.local nginx.local`
- [x] ArgoCD UI accessible via `http://argocd.local` (or `https://argocd.local:31755`)
- [x] Guestbook accessible via `http://guestbook.local`
- [x] Nginx Demo accessible via `http://nginx.local`
- [x] kube-prometheus-stack Helm release deployed in `monitoring` namespace
- [x] Grafana accessible via `http://grafana.local` (or `https://grafana.local:31755`)
- [x] ArgoCD metrics ServiceMonitor created and targets scraped by Prometheus
- [x] Grafana dashboard ID 14584 (ArgoCD) imported and displaying data
- [x] ResourceQuotas applied and enforced on `guestbook` and `nginx-demo` namespaces

## Files Involved

| File | Role |
|------|------|
| `infra/ingress/argocd.yaml` | Ingress rule: `argocd.local` → `argocd-server:80` |
| `infra/ingress/guestbook.yaml` | Ingress rule: `guestbook.local` → `guestbook:80` |
| `infra/ingress/nginx-demo.yaml` | Ingress rule: `nginx.local` → `nginx-demo:80` |
| `infra/ingress/README.md` | Access guide with NodePort/hostPort details and troubleshooting |
| `infra/monitoring/values.yaml` | Helm values for kube-prometheus-stack (Grafana ingress, no persistence, no AlertManager) |
| `infra/monitoring/argocd-servicemonitor.yaml` | ServiceMonitor scraping `argocd-metrics:8082` at 30s interval |
| `infra/monitoring/README.md` | Architecture diagram, access URLs, dashboard list, Helm upgrade guide |
| `infra/quotas/guestbook-quota.yaml` | ResourceQuota: 100m/500m CPU, 128Mi/512Mi Mem, max 10 pods |
| `infra/quotas/nginx-demo-quota.yaml` | ResourceQuota: 100m/500m CPU, 128Mi/512Mi Mem, max 10 pods |
| `infra/quotas/README.md` | Quota summary table, apply/verify commands |
| `infra/README.md` | Top-level infra overview linking all three subdirectories |
