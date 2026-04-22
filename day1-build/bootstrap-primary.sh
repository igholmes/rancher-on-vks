#!/bin/bash
set -euo pipefail

RKE2_VERSION="${RKE2_VERSION:-v1.32.3+rke2r1}"
RANCHER_VERSION="${RANCHER_VERSION:-2.11.1}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.17.1}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-rancher.example.com}"

LOG_FILE="/var/log/bootstrap-primary.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Installing RKE2 server ==="
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="$RKE2_VERSION" sh -

systemctl enable rke2-server
systemctl start rke2-server

echo "=== Waiting for RKE2 to be ready ==="
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="$PATH:/var/lib/rancher/rke2/bin"

until kubectl get nodes | grep -q " Ready"; do
  echo "Waiting for node to be Ready..."
  sleep 10
done

echo "=== Installing Helm ==="
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "=== Installing cert-manager ==="
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml"

helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version "$CERT_MANAGER_VERSION" \
  --wait

echo "=== Waiting for cert-manager ==="
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s

echo "=== Installing Rancher ==="
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname="$RANCHER_HOSTNAME" \
  --set bootstrapPassword=admin \
  --set replicas=1 \
  --version "$RANCHER_VERSION" \
  --wait

echo "=== Waiting for Rancher ==="
kubectl rollout status deployment/rancher -n cattle-system --timeout=300s

echo "=== Bootstrap complete ==="
echo "Rancher is available at: https://${RANCHER_HOSTNAME}"
echo "Initial bootstrap password: admin"
