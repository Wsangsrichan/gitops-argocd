# gitops-argocd

GitOps repository for ArgoCD on Kubernetes v1.30. Contains bootstrap manifests,
AppProjects, and Application definitions managed by ArgoCD.

## Prerequisites

- kubectl configured with cluster access
- Kubernetes cluster v1.30+
- argocd CLI (`argocd login`)
- GitLab account with PAT (Personal Access Token)

## Quick Start

### 1. Install ArgoCD

```bash
kubectl apply -f bootstrap/namespace.yaml
kubectl apply -f bootstrap/install.yaml -n argocd
```

Wait for all pods to be ready:

```bash
kubectl get pods -n argocd -w
```

### 2. Access ArgoCD

```bash
# Port-forward the API server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get initial admin password
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d
```

Open https://localhost:8080 and login with `admin` / the password above.

### 3. Configure GitLab Repository

1. Create a GitLab PAT with `read_repository` scope
2. Create a repository credential secret:

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
  url: https://gitlab.example.com
  username: <gitlab-username>
  password: <gitlab-pat>
EOF
```

> **Important:** The GitLab PAT is NOT stored in Git. Apply it manually via kubectl.
> This secret is gitignored (see `.gitignore`).

### 4. Deploy AppProject and Applications

```bash
# Create the AppProject
kubectl apply -f projects/demo-project.yaml

# Deploy the App of Apps (manages all child applications)
kubectl apply -f argocd/root-app.yaml
```

### 5. Sync Applications

```bash
# Via CLI
argocd app sync root-app --cascade

# Or open the ArgoCD UI and click "Sync" on each application
```

## Directory Structure

```
gitops-argocd/
├── bootstrap/              # ArgoCD installation
│   ├── namespace.yaml      # argocd namespace
│   └── install.yaml        # ArgoCD v2.14 core manifest
├── projects/               # AppProject definitions
│   └── demo-project.yaml   # RBAC-bounded demo project
├── apps/                   # Application definitions
│   ├── guestbook/          # Helm-based demo (nginx)
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── templates/
│   │   └── Application.yaml
│   └── nginx-demo/         # Kustomize-based demo
│       ├── base/
│       └── Application.yaml
└── argocd/                 # App of Apps pattern
    └── root-app.yaml       # Parent application
```

## GitLab PAT Setup

1. Go to **GitLab → Settings → Access Tokens**
2. Create token with scope: `read_repository`
3. Store securely — never commit to Git

## Sync Policy

Phase 1 uses **manual sync** for safety. No automated sync or prune.

## Verification

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# List applications
argocd app list

# Check app status
argocd app get guestbook
argocd app get nginx-demo

# Port-forward demo apps
kubectl port-forward svc/guestbook -n guestbook 8081:80
kubectl port-forward svc/nginx-demo -n nginx-demo 8082:80
```
