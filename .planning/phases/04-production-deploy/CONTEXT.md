# Phase 4 — Context: Production Cluster Redeployment

## Background
Phase 1-3 were deployed on a local single-node kind cluster with kind-specific workarounds (NodePort, localhost domains, /etc/hosts entries). Phase 4 redeploys everything on a production-grade 6-node Kubernetes cluster on DigitalOcean.

## Target Cluster

| Component | Detail |
|-----------|--------|
| Provider | DigitalOcean |
| Control Plane | 3 nodes (controlplan-0, controlplan-1, controlplan-2) |
| Worker Nodes | 3 nodes (workernode-0, workernode-1, workernode-2) |
| HA Proxy | 178.128.104.161:8443 |
| Kubernetes | v1.32.1 |
| CNI | Calico (VXLAN CrossSubnet) |
| OS | Ubuntu 24.04.4 LTS |
| Container Runtime | containerd 2.2.3 |

## Key Differences: Kind → Production

| Aspect | Kind (Phase 1-3) | Production (Phase 4) |
|--------|-------------------|----------------------|
| Nodes | 1 node | 6 nodes (3CP + 3W) |
| ArgoCD Mode | Core | HA (pinned to controlplan-0, replicas=1) |
| Storage | No StorageClass | local-path (Rancher provisioner) |
| Ingress Access | NodePort + /etc/hosts | NGINX Ingress + ipptt.com |
| Domains | *.local | *.ipptt.com |
| DNS | Working (single node) | Broken (inter-node port 53 blocked) |
| SealedSecrets | v0.27 | v0.28 |
| Prometheus + Grafana | kube-prometheus-stack (Operator) | Standalone Helm charts |

## Critical Issue: Inter-Node DNS Blocked

Port 53 (UDP/TCP) traffic between DigitalOcean nodes is blocked — likely cloud firewall at the DO account level. Pods on any node except controlplan-0 cannot reach CoreDNS.

### Symptoms
- Pods on worker/other-CP nodes: `dial udp 10.96.0.10:53: i/o timeout`
- Pod-to-pod HTTP works fine (TCP on any port except 53)
- CoreDNS metrics endpoint (TCP:9153) reachable from all nodes
- Test pod on controlplan-0 → DNS works; same test on controlplan-1 → fails

### Workaround Applied
1. CoreDNS scaled to 1 replica (naturally lands on controlplan-0)
2. All ArgoCD components pinned to controlplan-0 via `nodeSelector: kubernetes.io/hostname: controlplan-0`
3. Control plane taints removed to allow workload scheduling on CP nodes

### Future Fix
Open UDP/TCP port 53 between all nodes on DigitalOcean cloud firewall, then:
- Scale CoreDNS back to 2 replicas
- Remove nodeSelector from ArgoCD deployments/statefulset
- Re-add control plane taints for security isolation

## ArgoCD Version Issue
The initial install used v2.14.0-rc7 (from repo's old `bootstrap/install.yaml`) which has a `sync: unlock of unlocked mutex` fatal crash when Redis DNS lookup fails. Switched to ArgoCD stable v2.14 from upstream manifest — no crash, stable operation.

## Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| ArgoCD version | v2.14 stable (HA mode) | rc7 crashes on DNS race condition; HA for failover readiness |
| Ingress domain | *.ipptt.com | User's domain for production access |
| Grafana password | admin/admin | Dev/demo convenience |
| StorageClass | local-path | No cloud CSI available, bare-metal nodes |
| NGINX Ingress type | NodePort (32431/30364) | No cloud LoadBalancer available |
| Prometheus chart | Standalone prometheus-community/prometheus | Simpler than kube-prometheus-stack Operator |

## ArgoCD HA Deployment (2026-05-14)

Successfully deployed ArgoCD v2.14 in HA mode. Key components:
- **Redis HA**: StatefulSet with 3 containers (redis, sentinel, split-brain-fix) + HAProxy for sentinel discovery
- **Pod Anti-Affinity**: HA components use `podAntiAffinity` to spread across nodes — incompatible with DNS workaround
- **Replicas**: All scaled to 1 pending inter-node DNS fix

### HA Failover Architecture
```
argocd-server → argocd-redis-ha-haproxy:26379 (sentinel) → argocd-redis-ha-server-*:6379 (redis)
```
When DNS is fixed and replicas are scaled:
- 3 Redis servers: 1 master + 2 replicas (auto-failover via sentinel)
- 3 HAProxy instances: discover master via sentinel, route traffic
- 2 Repo servers + 2 API servers: for redundancy
