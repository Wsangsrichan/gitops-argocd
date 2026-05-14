# Ingress Access Guide

NGINX Ingress Controller running in **kind** cluster. Since kind doesn't expose ports 80/443 to the
host directly, services are accessed via **NodePort**.

## Hosts File

Ensure `/etc/hosts` maps the ingress domains to your kind node IP:

```
172.19.0.2 argocd.local guestbook.local nginx.local
```

> **Auto-detect node IP:** `kubectl get node -o jsonpath='{.items[0].status.addresses[0].address}'`

## NodePort Access

| Service | HTTP | HTTPS |
|---------|------|-------|
| **All** | `http://<node-ip>:30920` | `https://<node-ip>:31755` |

### Direct Access (NodePort + Host header)

```bash
# ArgoCD UI
curl -k https://172.19.0.2:31755 -H "Host: argocd.local"
# → 200  (or open in browser: https://argocd.local:31755)

# Guestbook
curl -k https://172.19.0.2:31755 -H "Host: guestbook.local"
# → 200  (or open in browser: https://guestbook.local:31755)

# Nginx Demo
curl -k https://172.19.0.2:31755 -H "Host: nginx.local"
# → 200  (or open in browser: https://nginx.local:31755)
```

### Browser Access (with /etc/hosts configured)

With the hosts file entry above, open in browser:

| App | URL |
|-----|-----|
| **ArgoCD UI** | `https://argocd.local:31755` |
| **Guestbook** | `https://guestbook.local:31755` |
| **Nginx Demo** | `https://nginx.local:31755` |

HTTP also works:
- `http://argocd.local:30920`
- `http://guestbook.local:30920`
- `http://nginx.local:30920`

## Alternative: kubectl port-forward

For development without Ingress/NodePort:

```bash
# ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:80
# → http://localhost:8080

# Guestbook
kubectl port-forward -n guestbook svc/guestbook 8081:80
# → http://localhost:8081

# Nginx Demo
kubectl port-forward -n nginx-demo svc/nginx-demo 8082:80
# → http://localhost:8082
```

## Troubleshooting

```bash
# Check NGINX Ingress is running
kubectl get pods -n ingress-nginx

# Check Ingress resources
kubectl get ingress -A

# Test connectivity
curl -vk https://172.19.0.2:31755 -H "Host: guestbook.local"

# If host header is missing, Ingress returns 404 (default backend)
```

## Ingress Resources

| File | Host | Backend Service | Namespace |
|------|------|-----------------|-----------|
| `argocd.yaml` | `argocd.local` | `argocd-server:80` | `argocd` |
| `guestbook.yaml` | `guestbook.local` | `guestbook:80` | `guestbook` |
| `nginx-demo.yaml` | `nginx.local` | `nginx-demo:80` | `nginx-demo` |
