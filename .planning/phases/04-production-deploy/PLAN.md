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

## Part 4b — ArgoCD HA Installation

### Task 4b-1 — Clean Previous ArgoCD
```bash
kubectl delete namespace argocd --wait=true --timeout=120s
```

### Task 4b-2 — Install ArgoCD HA
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.0/manifests/ha/install.yaml
```

HA components: application-controller (StatefulSet), redis-ha-server (StatefulSet, 3 containers: redis+sentinel+split-brain-fix), redis-ha-haproxy (Deployment), plus standard components (dex, notifications, repo-server, server).

### Task 4b-3 — Scale to 1 Replica (DNS Workaround)
Pod anti-affinity prevents multiple replicas on same node. Since all pods must run on controlplan-0 (DNS workaround), scale down:
```bash
kubectl scale deployment -n argocd argocd-redis-ha-haproxy --replicas=1
kubectl scale statefulset -n argocd argocd-redis-ha-server --replicas=1
kubectl scale deployment -n argocd argocd-repo-server --replicas=1
kubectl scale deployment -n argocd argocd-server --replicas=1
```

### Task 4b-4 — Handle Stale ReplicaSets
HA manifest creates new ReplicaSets; old non-HA RS may still exist. Scale old ones to 0:
```bash
kubectl get rs -n argocd | grep '0.*0.*0' | awk '{print $1}' | while read rs; do
  kubectl scale rs -n argocd $rs --replicas=0
done
```

### Task 4b-5 — CRD Finalizer Issue
Previous CRD deletion may leave stuck `customresourcecleanup` finalizer. Fix:
```bash
kubectl patch crd applications.argoproj.io --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.0/manifests/ha/install.yaml
```

### Task 4b-6 — Get Admin Password + Create Ingress
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl apply -f infra/ingress/argocd.yaml
```

**Verification**: 8 pods all 1/1 Running on controlplan-0, ingress returns 200.

### HA vs Non-HA Comparison
| Component | Non-HA | HA |
|-----------|--------|-----|
| Redis | Single `argocd-redis` pod | `argocd-redis-ha-server` StatefulSet (redis+sentinel) + `argocd-redis-ha-haproxy` Deployment |
| Failover | None | Sentinel-based automatic failover |
| Replicas (current) | 1 | 1 (limited by DNS workaround) |
| Replicas (target) | 1 | haproxy=3, redis=3, repo-server=2, server=2 |

### HA Failover Architecture
```
argocd-server → argocd-redis-ha-haproxy:26379 (sentinel) → argocd-redis-ha-server-*:6379 (redis)
```
When DNS fixed and replicas scaled:
- 3 Redis servers: 1 master + 2 replicas (auto-failover via sentinel)
- 3 HAProxy instances: discover master via sentinel, route traffic
- 2 Repo servers + 2 API servers: for redundancy

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
argocd:      ArgoCD HA (8 pods on controlplan-0)
guestbook:   1 pod
nginx-demo:  2 pods
monitoring: 12 pods (Prometheus + Grafana)
ingress-nginx: 1 pod (worker node)
kube-system: SealedSecrets + CoreDNS (1 replica)
```

### Known Issues
- **DNS blocked between nodes**: Workaround — CoreDNS=1 + ArgoCD pinned to CP0. Fix: open port 53 on DO firewall.
- **HA scaled to 1**: ArgoCD HA deployed but all replicas=1 due to DNS workaround. Scale up after DNS resolved.
- **Grafana datasource**: Manual Prometheus connection needed (`http://prometheus-server.monitoring.svc.cluster.local`).
