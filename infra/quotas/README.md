# Resource Quotas

ResourceQuota manifests to prevent demo workloads from consuming all cluster resources.

## Quotas

| Namespace   | CPU Requests | CPU Limits | Memory Requests | Memory Limits | Max Pods |
|-------------|-------------|------------|-----------------|---------------|----------|
| guestbook   | 100m        | 500m       | 128Mi           | 512Mi         | 10       |
| nginx-demo  | 100m        | 500m       | 128Mi           | 512Mi         | 10       |

## Files

- `guestbook-quota.yaml` — ResourceQuota for the `guestbook` namespace
- `nginx-demo-quota.yaml` — ResourceQuota for the `nginx-demo` namespace

## Apply

```bash
kubectl apply -f infra/quotas/guestbook-quota.yaml
kubectl apply -f infra/quotas/nginx-demo-quota.yaml
```

## Verify

```bash
kubectl get resourcequota -n guestbook
kubectl get resourcequota -n nginx-demo
kubectl describe resourcequota guestbook-quota -n guestbook
kubectl describe resourcequota nginx-demo-quota -n nginx-demo
```
