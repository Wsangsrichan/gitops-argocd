# Phase 2 — Deployment Plan

7 tasks to deploy ArgoCD, connect GitLab, and verify demo apps.

## Task 1 — Install ArgoCD

**Files:** `bootstrap/namespace.yaml`, `bootstrap/install.yaml`, `bootstrap/install.sh`
**Time:** ~3-5 min

```bash
chmod +x bootstrap/install.sh
./bootstrap/install.sh
```

Script does:
1. Check prerequisites (kubectl, cluster access)
2. Create `argocd` namespace
3. Apply install manifest
4. Wait for `argocd-server`, `argocd-repo-server`, `argocd-applicationset-controller` to be ready

**Verification:**
```bash
kubectl get pods -n argocd
# Expected: all pods Running
```

---

## Task 2 — Access Dashboard

**Files:** none (kubectl only)
**Time:** ~2 min

```bash
# Terminal 1 — port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Terminal 2 — get password
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d && echo
```

Open https://localhost:8080 → login `admin` / password

**Verification:** Dashboard loads, login succeeds

---

## Task 3 — Connect GitLab Repo

**Files:** `bootstrap/install.sh` (references), new kubectl Secret
**Time:** ~3 min

Replace `<gitlab-username>` and `<gitlab-pat>` with real values:

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

**Verification:**
```bash
# Via CLI (after port-forward login)
argocd repo list
# Expected: repo URL shown, status Successful

# Via UI: Settings → Repositories
```

---

## Task 4 — Create AppProject

**Files:** `projects/demo-project.yaml`
**Time:** ~1 min

```bash
kubectl apply -f projects/demo-project.yaml
```

**Verification:**
```bash
argocd proj list
# Expected: demo-project listed
```

---

## Task 5 — Deploy Demo Apps

**Files:** `argocd/root-app.yaml`, `apps/guestbook/Application.yaml`, `apps/nginx-demo/Application.yaml`
**Time:** ~2 min

### Option A: App of Apps (recommended)

```bash
kubectl apply -f argocd/root-app.yaml
```

### Option B: Individual

```bash
kubectl apply -f apps/guestbook/Application.yaml
kubectl apply -f apps/nginx-demo/Application.yaml
```

**Verification:**
```bash
argocd app list
# Expected: guestbook, nginx-demo listed, status OutOfSync/Healthy
```

---

## Task 6 — Sync Apps

**Files:** none (CLI/UI)
**Time:** ~2 min

```bash
# Sync all via parent
argocd app sync root-app --cascade

# Or individually
argocd app sync guestbook
argocd app sync nginx-demo
```

**Verification:**
```bash
argocd app list
# Expected: all apps show "Synced" and "Healthy"
```

---

## Task 7 — Verify Workloads

**Files:** none (kubectl only)
**Time:** ~2 min

```bash
# Check deployed pods
kubectl get pods -n guestbook
kubectl get pods -n nginx-demo

# Check services
kubectl get svc -n guestbook
kubectl get svc -n nginx-demo

# Port-forward and test
kubectl port-forward svc/guestbook -n guestbook 8081:80 &
kubectl port-forward svc/nginx-demo -n nginx-demo 8082:80 &

# Test endpoints
curl -s -o /dev/null -w "%{http_code}" http://localhost:8081  # Expect 200
curl -s -o /dev/null -w "%{http_code}" http://localhost:8082  # Expect 200
```

**Verification:** Both endpoints return HTTP 200, pods Running, ArgoCD UI shows Synced+Healthy

---

## Summary

| Task | Time | Cumulative |
|------|------|------------|
| 1. Install ArgoCD | 3-5 min | ~5 min |
| 2. Access Dashboard | 2 min | ~7 min |
| 3. Connect GitLab | 3 min | ~10 min |
| 4. Create AppProject | 1 min | ~11 min |
| 5. Deploy Demo Apps | 2 min | ~13 min |
| 6. Sync Apps | 2 min | ~15 min |
| 7. Verify Workloads | 2 min | ~17 min |

**Total estimated time: 15-20 minutes** (including cluster scheduling delays)
