# Phase 4 — Production Cluster Redeployment Plan

Redeploy gitops-argocd from single-node kind to 6-node DigitalOcean cluster with `*.ipptt.com` ingress.

---

## Prerequisites

### Prereq-1 — New Cluster Access
```bash
kubectl cluster-info
# Expected: Kubernetes control plane at https://178.128.104.161:8443
kubectl get nodes
# Expected: 6 nodes — 3 control-plane, 3 worker
```

### Prereq-2 — Install NGINX Ingress Controller
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/baremetal/deploy.yaml
```
NodePort: `80:32431`, `443:30364`

### Prereq-3 — Create StorageClass
```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

---

## Part 4a — DNS Workaround

**Root cause**: Inter-node port 53 (UDP/TCP) blocked — likely DigitalOcean cloud firewall. Pods on any node except controlplan-0 cannot reach CoreDNS at `10.96.0.10:53`.

### Task 4a-1 — Scale CoreDNS to 1
```bash
kubectl scale deployment -n kube-system coredns --replicas=1
```

### Task 4a-2 — Remove Control Plane Taints
```bash
kubectl taint nodes -l node-role.kubernetes.io/control-plane node-role.kubernetes.io/control-plane:NoSchedule-
```

### Task 4a-3 — Pin ArgoCD to controlplan-0
```bash
for deploy in argocd-applicationset-controller argocd-dex-server \
  argocd-notifications-controller argocd-redis argocd-repo-server argocd-server; do
  kubectl patch deployment -n argocd $deploy --type=strategic \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"controlplan-0"}}}}}'
done
kubectl patch statefulset -n argocd argocd-application-controller --type=strategic \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"controlplan-0"}}}}}'
```

**Verification**: All 7 ArgoCD pods on controlplan-0, 1/1 Running.

---

## Part 4b — ArgoCD Installation

### Task 4b-1 — Install ArgoCD (Stable v2.14)
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
**Note**: Used stable upstream — not repo's `bootstrap/install.yaml` (which had v2.14.0-rc7 with DNS crash bug).

### Task 4b-2 — Get Admin Password
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Task 4b-3 — Create Ingress for ArgoCD
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.ipptt.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
```

---

## Part 4c — GitOps Deployment

### Task 4c-1 — Create AppProject
```bash
kubectl apply -f projects/demo-project.yaml
```

### Task 4c-2 — Deploy App of Apps
```bash
kubectl apply -f argocd/root-app.yaml
```
Discovers child apps via `*/Application.yaml` pattern in `apps/`.

### Task 4c-3 — Verify
```bash
kubectl get app -n argocd
# Expected: guestbook Synced/Healthy, nginx-demo Synced/Healthy, root-app Synced/Healthy
```

---

## Part 4d — Ingress Setup

### Task 4d-1 — Guestbook (`guestbook.ipptt.com`)
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: guestbook
  namespace: guestbook
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: guestbook.ipptt.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: guestbook
            port:
              number: 80
```

### Task 4d-2 — Nginx Demo (`nginx.ipptt.com`)
Same structure, namespace `nginx-demo`, service `nginx-demo`.

### Task 4d-3 — Grafana (`grafana.ipptt.com`)
Same structure, namespace `monitoring`, service `grafana`.

**Verification**: `kubectl get ingress -A` — 4 hosts, curl returns 200 for all.

---

## Part 4e — Infrastructure

### Task 4e-1 — SealedSecrets v0.28
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.28.0/controller.yaml
```

### Task 4e-2 — Prometheus
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring --create-namespace \
  --set server.persistentVolume.enabled=true \
  --set server.persistentVolume.storageClass=local-path \
  --set server.persistentVolume.size=5Gi --wait --timeout 10m
```

### Task 4e-3 — Grafana
```bash
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring --create-namespace \
  --set persistence.enabled=true --set persistence.storageClassName=local-path \
  --set persistence.size=2Gi --set adminPassword=admin --wait --timeout 10m
```
Credentials: `admin` / `admin`

### Task 4e-4 — ResourceQuotas
```bash
kubectl apply -f resource-quotas/guestbook-quota.yaml
kubectl apply -f resource-quotas/nginx-demo-quota.yaml
```

| Namespace | CPU Req | CPU Limit | Mem Req | Mem Limit | Max Pods |
|-----------|---------|-----------|---------|-----------|----------|
| guestbook | 100m | 500m | 128Mi | 512Mi | 10 |
| nginx-demo | 100m | 500m | 128Mi | 512Mi | 10 |

---

## Final State

### Access URLs (DNS setup required)
| Service | URL | Auth |
|---------|-----|------|
| ArgoCD | https://argocd.ipptt.com | admin / `...` |
| Guestbook | https://guestbook.ipptt.com | — |
| Nginx Demo | https://nginx.ipptt.com | — |
| Grafana | https://grafana.ipptt.com | admin / admin |

### Cluster Snapshot
```
6 nodes: 3 CP + 3 W (all Ready)
argocd:      7 pods (controlplan-0)
guestbook:   1 pod
nginx-demo:  2 pods
monitoring: 12 pods (Prometheus + Grafana)
ingress-nginx: 1 pod (worker node)
kube-system: SealedSecrets + CoreDNS (1 replica)
```

### Known Issues
- **DNS blocked between nodes**: Workaround — CoreDNS=1 + ArgoCD pinned to CP0. Fix: open port 53 on DO firewall.
- **No HA**: ArgoCD single point of failure on controlplan-0. Fix after DNS resolved.
- **Grafana datasource**: Manual Prometheus connection needed (`http://prometheus-server.monitoring.svc.cluster.local`).
