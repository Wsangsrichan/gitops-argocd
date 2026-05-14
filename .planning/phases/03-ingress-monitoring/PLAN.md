# Phase 3 — Implementation Plan

Three sub-phases to deploy Ingress, Monitoring, and Resource Quotas on the kind cluster.

---

## Part 3a — NGINX Ingress Controller & Ingress Rules

### Task 3a-1 — Deploy NGINX Ingress Controller

**Files:** none (Helm/kubectl)
**Time:** ~3-5 min

```bash
# Add Helm repo and install
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.hostPort.enabled=true \
  --set controller.service.type=NodePort
```

On kind, the controller is deployed with `hostPort: 80` and `hostPort: 443` so the kind node's ports 80/443 map directly to the NGINX container. The Kubernetes Service is type `NodePort` as a fallback.

**Verification:**
```bash
kubectl get pods -n ingress-nginx
# Expected: ingress-nginx-controller-* Running 1/1
```

---

### Task 3a-2 — Discover Kind Node IP

**Files:** none (kubectl)
**Time:** ~1 min

```bash
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[0].address}')
echo "Kind node IP: $NODE_IP"
# Expected: 172.19.0.2 (or similar Docker bridge IP)
```

This IP is needed for `/etc/hosts` entries. It **can change** when the kind cluster is restarted — re-run after any cluster restart.

---

### Task 3a-3 — Configure /etc/hosts

**Files:** `/etc/hosts` (host machine)
**Time:** ~1 min

```bash
# Add to /etc/hosts (requires sudo)
echo "172.19.0.2 argocd.local guestbook.local nginx.local grafana.local" | sudo tee -a /etc/hosts
```

Alternatively, use port-forward for direct access (no hosts file needed):
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:80
```

**Verification:**
```bash
ping -c 1 argocd.local
# Expected: 172.19.0.2 responds
```

---

### Task 3a-4 — Create Ingress Resources

**Files:** `infra/ingress/argocd.yaml`, `infra/ingress/guestbook.yaml`, `infra/ingress/nginx-demo.yaml`
**Time:** ~1 min

```bash
kubectl apply -f infra/ingress/
```

Each Ingress uses `ingressClassName: nginx` and maps a `.local` host to its backend Service on port 80.

| Ingress | Host | Backend | Namespace |
|---------|------|---------|-----------|
| argocd | argocd.local | argocd-server:80 | argocd |
| guestbook | guestbook.local | guestbook:80 | guestbook |
| nginx-demo | nginx.local | nginx-demo:80 | nginx-demo |

**Verification:**
```bash
kubectl get ingress -A
# Expected: all three show nginx address

curl -s -o /dev/null -w "%{http_code}" http://argocd.local
# Expected: 200
curl -s -o /dev/null -w "%{http_code}" http://guestbook.local
# Expected: 200
curl -s -o /dev/null -w "%{http_code}" http://nginx.local
# Expected: 200
```

---

## Part 3b — Monitoring Stack (Prometheus + Grafana)

### Task 3b-1 — Install kube-prometheus-stack via Helm

**Files:** `infra/monitoring/values.yaml`
**Time:** ~3-5 min

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values infra/monitoring/values.yaml
```

What gets deployed:
- **Prometheus** (1 replica, 2h retention, no persistence)
- **Grafana** (1 replica, admin/admin, ingress at grafana.local, no persistence)
- **Node Exporter** (per-node metrics)
- **Kube State Metrics** (cluster state)
- **Prometheus Operator** (manages ServiceMonitors + PrometheusRules)
- **AlertManager** (disabled — not needed for dev)

**Verification:**
```bash
kubectl get pods -n monitoring
# Expected: prometheus-*, grafana-*, node-exporter-*, kube-state-metrics-*, operator-* all Running
```

---

### Task 3b-2 — Verify Grafana Access

**Files:** none
**Time:** ~2 min

```bash
# With /etc/hosts configured:
open http://grafana.local

# Or via NodePort:
open http://172.19.0.2:30920
# (then navigate with Host header or use port-forward)
```

**Credentials:** `admin` / `admin`

**Verification:** Grafana login page loads, login succeeds, Prometheus datasource is auto-provisioned.

---

### Task 3b-3 — Create ArgoCD ServiceMonitor

**Files:** `infra/monitoring/argocd-servicemonitor.yaml`
**Time:** ~1 min

```bash
kubectl apply -f infra/monitoring/argocd-servicemonitor.yaml
```

This tells Prometheus to scrape ArgoCD's metrics endpoint (`argocd-metrics.argocd:8082/metrics`) every 30 seconds. The `release: monitoring` label ensures the Prometheus instance discovers it.

**Verification:**
```bash
# Check ServiceMonitor exists
kubectl get servicemonitor -n argocd
# Expected: argocd-metrics

# Check Prometheus targets
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets
# Expected: argocd-metrics target UP
```

---

### Task 3b-4 — Import ArgoCD Dashboard (Grafana ID 14584)

**Files:** none (API call)
**Time:** ~2 min

```bash
# Port-forward Grafana for API access
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 &

# Import dashboard via Grafana API
GRAFANA_URL="http://admin:admin@localhost:3000"
DASHBOARD_ID="14584"

curl -s -X POST "${GRAFANA_URL}/api/gnet/dashboards/import" \
  -H "Content-Type: application/json" \
  -d "{\"dashboardId\":${DASHBOARD_ID},\"overwrite\":true,\"inputs\":[{\"name\":\"DS_PROMETHEUS\",\"type\":\"datasource\",\"pluginId\":\"prometheus\",\"value\":\"Prometheus\"}]}"
```

**Verification:**
- Open Grafana → Dashboards → Browse → "ArgoCD"
- Dashboard displays: sync status, application count, health metrics, API server stats

---

## Part 3c — Resource Quotas

### Task 3c-1 — Apply ResourceQuota Manifests

**Files:** `infra/quotas/guestbook-quota.yaml`, `infra/quotas/nginx-demo-quota.yaml`
**Time:** ~1 min

```bash
kubectl apply -f infra/quotas/guestbook-quota.yaml
kubectl apply -f infra/quotas/nginx-demo-quota.yaml
```

| Namespace | CPU Requests | CPU Limits | Memory Requests | Memory Limits | Max Pods |
|-----------|-------------|------------|-----------------|---------------|----------|
| guestbook | 100m | 500m | 128Mi | 512Mi | 10 |
| nginx-demo | 100m | 500m | 128Mi | 512Mi | 10 |

---

### Task 3c-2 — Verify Quota Enforcement

**Files:** none (kubectl)
**Time:** ~1 min

```bash
# List quotas
kubectl get resourcequota -n guestbook
kubectl get resourcequota -n nginx-demo

# Detailed view
kubectl describe resourcequota guestbook-quota -n guestbook
kubectl describe resourcequota nginx-demo-quota -n nginx-demo

# Check current usage
kubectl get resourcequota guestbook-quota -n guestbook \
  -o jsonpath='{.status}' | jq .
```

**Verification:**
- Both quotas show `Used` values reflecting currently running pods
- No `Hard` limits exceeded (status is clean)

---

## Summary

| Task | Time | Cumulative |
|------|------|------------|
| 3a-1. Deploy NGINX Ingress Controller | 3-5 min | ~5 min |
| 3a-2. Discover Kind Node IP | 1 min | ~6 min |
| 3a-3. Configure /etc/hosts | 1 min | ~7 min |
| 3a-4. Create Ingress Resources | 1 min | ~8 min |
| 3b-1. Install kube-prometheus-stack | 3-5 min | ~13 min |
| 3b-2. Verify Grafana Access | 2 min | ~15 min |
| 3b-3. Create ArgoCD ServiceMonitor | 1 min | ~16 min |
| 3b-4. Import ArgoCD Dashboard | 2 min | ~18 min |
| 3c-1. Apply ResourceQuota Manifests | 1 min | ~19 min |
| 3c-2. Verify Quota Enforcement | 1 min | ~20 min |

**Total estimated time: 15-20 minutes** (including Helm chart downloads and pod scheduling delays)
