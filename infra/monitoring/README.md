# Monitoring — Prometheus + Grafana Stack

Phase 3b monitoring infrastructure for the GitOps cluster.

## Access

| Component  | URL                        | Credentials    |
|------------|----------------------------|----------------|
| **Grafana** | https://grafana.local      | admin / admin  |
| **Prometheus** | (internal only)         | —              |

### Prometheus Access

Prometheus has no ingress. Use port-forward for direct access:

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# Then open http://localhost:9090
```

## Dashboards

| Dashboard | Source | Status |
|-----------|--------|--------|
| ArgoCD | [Grafana ID 14584](https://grafana.com/grafana/dashboards/14584-argocd/) | Imported via API |
| Kubernetes cluster monitoring | Built-in (kube-prometheus-stack) | Auto-provisioned |
| Node Exporter | Built-in | Auto-provisioned |

Additional dashboards available from the [Prometheus Operator mixins](https://github.com/prometheus-operator/kube-prometheus).

## ServiceMonitors

ServiceMonitors tell Prometheus which services to scrape. The Prometheus instance is configured to discover ServiceMonitors with label `release: monitoring`.

### Adding a New ServiceMonitor

1. Create a ServiceMonitor manifest in `infra/monitoring/`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: <app-namespace>
  labels:
    release: monitoring        # Required — picked up by Prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: my-app-metrics
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

2. Apply:

```bash
kubectl apply -f infra/monitoring/my-app-servicemonitor.yaml
```

3. Verify in Prometheus UI → Status → Targets.

### Existing ServiceMonitors

| Name | Namespace | Target |
|------|-----------|--------|
| `argocd-metrics` | `argocd` | `argocd-metrics.argocd:8082` |
| `monitoring-kube-prometheus-prometheus` | `monitoring` | Built-in Kubernetes metrics |
| `monitoring-prometheus-node-exporter` | `monitoring` | Node-level metrics |
| `monitoring-kube-state-metrics` | `monitoring` | Cluster state metrics |

## Architecture

```
┌─────────────────────────────────────────────┐
│                  Kubernetes                  │
│                                             │
│  ┌──────────┐     ┌───────────────────┐     │
│  │ Prometheus│◀──▶│  ServiceMonitors  │     │
│  │  (monitoring)│   │  (label: release=monitoring)│
│  └────┬─────┘     └───────────────────┘     │
│       │                                      │
│  ┌────▼─────┐                               │
│  │  Grafana  │──── https://grafana.local     │
│  │ (monitoring)                              │
│  └──────────┘                               │
│                                             │
│  Data sources:                              │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐ │
│  │  ArgoCD   │  │  Node    │  │ Kube State │ │
│  │ Metrics   │  │ Exporter │  │  Metrics   │ │
│  │ :8082     │  │          │  │            │ │
│  └──────────┘  └──────────┘  └───────────┘ │
└─────────────────────────────────────────────┘
```

## Helm Values

The stack is deployed via the `kube-prometheus-stack` Helm chart. See [`values.yaml`](./values.yaml) for the current configuration:

- **AlertManager**: disabled (dev cluster)
- **Grafana**: ingress at grafana.local, no persistence
- **Prometheus**: 2h retention, no persistence
- **Node Exporter + Kube State Metrics**: enabled

To upgrade/reconfigure:

```bash
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f infra/monitoring/values.yaml
```
