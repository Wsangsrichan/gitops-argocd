# gitops-argocd — ArgoCD GitOps on Kubernetes v1.30

## Identity
**Project:** gitops-argocd
**Purpose:** GitOps repository for ArgoCD — bootstrap, AppProjects, and Application manifests
**Owner:** Haocomm
**Stack:** ArgoCD v2.14, Kubernetes v1.30, GitLab (source control), YAML/Kustomize/Helm
**Created:** 2026-05-14

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
└── argocd/                     # App of Apps (root)
    └── root-app.yaml           # Parent Application pointing to apps/
```

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| ArgoCD version | v2.14 | Stable on k8s 1.30, tested |
| Install mode | Core (non-HA) | Phase 1 — single cluster, no HA needed |
| Secret management | SealedSecrets ✅ | GitOps-native secrets via kubeseal; Phase 2b complete |
| Sync policy | Auto (prune + selfHeal) ✅ | Automated sync enabled on all apps; Phase 2b complete |
| Source control | GitLab | User requirement |
| Demo apps | Guestbook (Helm) + Nginx (Kustomize) | Show both Helm and Kustomize patterns |

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
- [ ] ArgoCD pods running in `argocd` namespace
- [ ] ArgoCD API server accessible (port-forward or Ingress)
- [ ] GitLab repo connected (status: Successful in Repositories)
- [ ] AppProject created (no errors)
- [ ] Application syncs successfully
- [ ] Guestbook accessible via port-forward
