#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.14.0}"
NAMESPACE="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_DEPLOYMENTS=("argocd-server" "argocd-repo-server" "argocd-applicationset-controller")
TIMEOUT="${TIMEOUT:-300}"

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

check_prerequisites() {
  command -v kubectl >/dev/null 2>&1 || error "kubectl not found. Install it first: https://kubernetes.io/docs/tasks/tools/"
  kubectl cluster-info >/dev/null 2>&1 || error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
  info "Prerequisites OK — kubectl $(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | head -1 | cut -d'"' -f4)"
}

create_namespace() {
  info "Creating namespace '${NAMESPACE}'..."
  kubectl apply -f "${SCRIPT_DIR}/namespace.yaml"
}

apply_manifest() {
  info "Applying ArgoCD ${ARGOCD_VERSION} install manifest..."
  kubectl apply -f "${SCRIPT_DIR}/install.yaml" -n "${NAMESPACE}"
}

wait_for_deployments() {
  info "Waiting for core deployments to be ready (timeout: ${TIMEOUT}s)..."
  local start elapsed
  start=$(date +%s)

  for deploy in "${EXPECTED_DEPLOYMENTS[@]}"; do
    info "  Waiting for ${deploy}..."
    if ! kubectl rollout status "deployment/${deploy}" -n "${NAMESPACE}" --timeout="${TIMEOUT}s"; then
      error "Deployment ${deploy} failed to become ready within ${TIMEOUT}s"
    fi
  done

  elapsed=$(( $(date +%s) - start ))
  info "All deployments ready in ${elapsed}s"
}

print_summary() {
  local password
  password=$(kubectl get secret argocd-initial-admin-secret \
    -n "${NAMESPACE}" -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "<not available>")

  echo ""
  echo "============================================="
  echo "  ArgoCD ${ARGOCD_VERSION} installed successfully"
  echo "============================================="
  echo ""
  echo "Dashboard access:"
  echo "  kubectl port-forward svc/argocd-server -n ${NAMESPACE} 8080:443"
  echo "  URL: https://localhost:8080"
  echo ""
  echo "Credentials:"
  echo "  Username: admin"
  echo "  Password: ${password}"
  echo ""
  echo "CLI login:"
  echo "  argocd login localhost:8080 --username admin --password '${password}' --insecure"
  echo ""
  echo "Next steps:"
  echo "  1. Connect GitLab repo (see README Step 4)"
  echo "  2. Apply AppProject:  kubectl apply -f projects/demo-project.yaml"
  echo "  3. Deploy apps:       kubectl apply -f argocd/root-app.yaml"
  echo "============================================="
}

main() {
  echo "ArgoCD Bootstrap Installer"
  echo "Version: ${ARGOCD_VERSION}"
  echo "Namespace: ${NAMESPACE}"
  echo ""

  check_prerequisites
  create_namespace
  apply_manifest
  wait_for_deployments
  print_summary
}

main "$@"
