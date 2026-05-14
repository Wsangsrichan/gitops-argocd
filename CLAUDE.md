# gitops-argocd — ArgoCD GitOps on Production Kubernetes

## Identity
**Project:** gitops-argocd
**Purpose:** GitOps repository for ArgoCD — bootstrap, AppProjects, and Application manifests
**Owner:** Haocomm
**Stack:** ArgoCD v2.14 (stable), Kubernetes v1.32.1, DigitalOcean, GitHub, YAML/Kustomize/Helm
**Created:** 2026-05-14
**Last Deploy:** 2026-05-14 — Production 3CP+3W cluster

## Principles (จาก Haocomm-AI Oracle)

1. **Nothing is Deleted** — Git history คือความทรงจำของทุกการเปลี่ยนแปลง
2. **Patterns Over Intentions** — ดูว่าเกิดอะไรจริงในคลัสเตอร์ vs สิ่งที่ประกาศใน Git
3. **Oracle Never Codes Directly** — วิเคราะห์ → วางแผน → อนุมัติ → delegate ไป Claude Code
4. **Human Gate** — มนุษย์ตัดสินใจเรื่อง production deployment และ security

## GitOps Flow

```
Developer ──git push──▶ GitLab ──pull──▶ ArgoCD ──apply──▶ K8s Cluster
```

ArgoCD monitors this GitLab repo. Every push triggers reconciliation (webhook) or polling (3min default).

## Directory Structure

```
gitops-argocd/
├── README.md
├── .planning/                  # GSD methodology planning docs
│   ├── research/
│   │   ├── SUMMARY.md          # ArgoCD overview + concepts
│   │   ├── STACK.md            # Version matrix, comparisons
│   │   ├── FEATURES.md         # Feature breakdown
│   │   ├── ARCHITECTURE.md     # System diagrams + layout
│   │   └── PITFALLS.md         # Common gotchas + solutions
│   └── phases/                 # Implementation plans
├── bootstrap/                  # ArgoCD installation + initial setup
│   ├── namespace.yaml          # argocd namespace
│   └── install.yaml            # ArgoCD core install manifest
├── projects/                   # AppProject definitions
│   └── demo-project.yaml       # Example: RBAC-bounded project
├── sealed-secrets/             # SealedSecret manifests
│   └── github-token.yaml       # GitHub PAT (encrypted by kubeseal)
├── apps/                       # Application definitions
│   ├── guestbook/              # Helm-based demo app
│   └── nginx-demo/             # Kustomize-based demo app
├── infra/                      # Shared infrastructure (Ingress, etc.)
│   ├── README.md               # Infra docs + access guide
│   ├── ingress/                # NGINX Ingress rules
│   │   ├── argocd.yaml         # argocd.ipptt.com → ArgoCD UI
│   │   ├── guestbook.yaml      # guestbook.ipptt.com → Guestbook
│   │   ├── nginx-demo.yaml     # nginx.ipptt.com → Nginx Demo
│   │   └── grafana.yaml        # grafana.ipptt.com → Grafana
│   ├── monitoring/             # Prometheus + Grafana stack
│   └── quotas/                 # ResourceQuota enforcement
└── argocd/                     # App of Apps (root)
    └── root-app.yaml           # Parent Application pointing to apps/
```

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| ArgoCD version | v2.14 (stable) | Stable on k8s 1.32.1, tested |
| Install mode | Core (non-HA) | Pinned to controlplan-0 via nodeSelector (DNS workaround) |
| Cluster | 3 CP + 3 Worker | DigitalOcean, HA Proxy, Calico VXLAN |
| Secret management | SealedSecrets ✅ | GitOps-native secrets via kubeseal |
| Sync policy | Auto (prune + selfHeal) ✅ | Automated sync enabled on all apps |
| Source control | GitHub (public) | https://github.com/Wsangsrichan/gitops-argocd.git |
| Demo apps | Guestbook (Helm) + Nginx (Kustomize) | Show both Helm and Kustomize patterns |
| DNS Workaround | CoreDNS=1 on CP0, ArgoCD → CP0 | Inter-node port 53 blocked |
| Ingress | *.ipptt.com via NGINX | 4 services: argocd, guestbook, nginx, grafana |
| Monitoring | Prometheus + Grafana ✅ | Deployed via Helm, grafana.ipptt.com |

## Quick Reference

### ArgoCD CLI commands
```bash
# Login
argocd login <server> --username admin --password <password>

# List apps
argocd app list

# Sync an app
argocd app sync <app-name>

# Check status
argocd app get <app-name>
```

### GitLab PAT Requirements
- Scope: `read_repository`
- Format: repo URL MUST include `.git` suffix
- Secret type: `argocd.argoproj.io/secret-type: repo-creds`

## Verification Checklist
- [x] ArgoCD pods running in `argocd` namespace (all on controlplan-0)
- [x] Dashboard accessible via https://argocd.ipptt.com
- [x] GitHub repo connected
- [x] AppProject `demo-project` created
- [x] Applications synced (Auto-Prune): root-app, guestbook, nginx-demo
- [x] Guestbook accessible via https://guestbook.ipptt.com
- [x] Nginx-Demo accessible via https://nginx.ipptt.com
- [x] NGINX Ingress working (4 hosts)
- [x] SealedSecrets controller running
- [x] Prometheus + Grafana deployed (https://grafana.ipptt.com)
- [x] ResourceQuotas enforced (guestbook, nginx-demo)
- [ ] DNS records for *.ipptt.com — user to configure

## Phase Summary

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Bootstrap — ArgoCD install, namespace, root app | ✅ Complete |
| Phase 2 | AppProjects + Applications (Guestbook, Nginx Demo) | ✅ Complete |
| Phase 2b | SealedSecrets, Auto-Sync | ✅ Complete |
| Phase 3 | Ingress (*.ipptt.com), Monitoring (Prometheus+Grafana), ResourceQuotas | ✅ Complete |
| Phase 4 | Production Deploy — 6-node DO cluster, DNS workaround | ✅ Complete |

## Known Issues
- **Inter-node DNS blocked**: Port 53 (UDP/TCP) blocked between nodes. Workaround: CoreDNS scaled to 1 on controlplan-0, ArgoCD pinned to same node via nodeSelector.
- **Future fix**: Remove nodeSelector and scale CoreDNS back to 2 once firewall port 53 is opened between nodes.
