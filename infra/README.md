# infra/ — Infrastructure Manifests

Shared infrastructure resources that support the cluster but are not application-specific.

## Structure

```
infra/
├── README.md              # This file
└── ingress/               # NGINX Ingress rules
    ├── argocd.yaml         # argocd.local → ArgoCD UI
    ├── guestbook.yaml      # guestbook.local → Guestbook demo app
    └── nginx-demo.yaml     # nginx.local → Nginx demo app
```

## Ingress Overview

| Ingress | Host | Backend Service | Namespace |
|---------|------|-----------------|-----------|
| argocd | argocd.local | argocd-server:80 | argocd |
| guestbook | guestbook.local | guestbook:80 | guestbook |
| nginx-demo | nginx.local | nginx-demo:80 | nginx-demo |

All Ingress resources use the `nginx` IngressClass backed by the NGINX Ingress Controller in the `ingress-nginx` namespace.

## Access

Add these entries to `/etc/hosts` for local development:

```
127.0.0.1 argocd.local guestbook.local nginx.local
```

Then access:
- ArgoCD UI: http://argocd.local
- Guestbook: http://guestbook.local
- Nginx Demo: http://nginx.local

## Apply

```bash
kubectl apply -f infra/ingress/
```
