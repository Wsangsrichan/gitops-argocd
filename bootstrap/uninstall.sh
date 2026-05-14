#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

confirm() {
  local prompt="$1"
  local response
  while true; do
    read -rp "${prompt} [y/N]: " response
    case "${response}" in
      [yY]|[yY][eE][sS]) return 0 ;;
      [nN]|[nN][oO]|"")   echo "Aborted."; exit 0 ;;
    esac
  done
}

remove_applications() {
  info "Removing ArgoCD Application resources..."
  kubectl delete applications --all -n "${NAMESPACE}" --ignore-not-found 2>/dev/null || true
  kubectl delete appprojects --all -n "${NAMESPACE}" --ignore-not-found 2>/dev/null || true
}

remove_install() {
  info "Removing ArgoCD install manifest..."
  kubectl delete -f "${SCRIPT_DIR}/install.yaml" -n "${NAMESPACE}" --ignore-not-found
}

remove_namespace() {
  info "Removing namespace '${NAMESPACE}'..."
  kubectl delete namespace "${NAMESPACE}" --ignore-not-found
}

remove_repo_creds() {
  info "Cleaning up GitLab repo credential secrets..."
  kubectl delete secret gitlab-repo-creds -n "${NAMESPACE}" --ignore-not-found 2>/dev/null || true
}

main() {
  echo "ArgoCD Uninstaller"
  echo "Namespace: ${NAMESPACE}"
  echo ""

  confirm "This will remove ArgoCD and ALL its resources from namespace '${NAMESPACE}'. Are you sure?"

  remove_applications
  remove_repo_creds
  remove_install
  remove_namespace

  echo ""
  echo "ArgoCD has been uninstalled."
  echo "Note: Cluster-scoped resources (CRDs) were NOT removed. To remove them:"
  echo "  kubectl delete crd applications.argoproj.io appprojects.argoproj.io"
}

main "$@"
