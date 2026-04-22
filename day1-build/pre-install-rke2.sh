#!/bin/bash
set -euo pipefail

# ============================================================
# Pre-install script for RKE2 primary server node
# Run this BEFORE bootstrap-primary.sh
# ============================================================

LOG_FILE="/var/log/pre-install-rke2.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ----------------------------------------------------------
# Prompt for configuration variables
# ----------------------------------------------------------
read -rp "Enter the VIP IP address [10.0.1.5]: " input
RKE2_VIP_IP="${input:-10.0.1.5}"

read -rp "Enter the VIP network interface [eth0]: " input
VIP_INTERFACE="${input:-eth0}"

read -rp "Enter the k9s version [v0.32.7]: " input
K9S_VERSION="${input:-v0.32.7}"

read -rp "Enter the domain suffix [lol]: " input
DOMAIN_SUFFIX="${input:-lol}"

echo ""
echo "=== RKE2 Pre-Install ==="
echo "VIP IP:        ${RKE2_VIP_IP}"
echo "VIP Interface: ${VIP_INTERFACE}"
echo "k9s Version:   ${K9S_VERSION}"
echo "Domain:        ${HOSTNAME}.${DOMAIN_SUFFIX}"
echo ""
read -rp "Proceed with these settings? [Y/n]: " confirm
if [[ "${confirm,,}" == "n" ]]; then
  echo "Aborted."
  exit 1
fi

# ----------------------------------------------------------
# 1. Create RKE2 self-installing manifest directory
# ----------------------------------------------------------
echo "=== Creating RKE2 manifest directory ==="
mkdir -p /var/lib/rancher/rke2/server/manifests/

# ----------------------------------------------------------
# 2. Install kube-vip into RKE2 self-installing manifests
# ----------------------------------------------------------
echo "=== Installing kube-vip manifest ==="
curl -sL kube-vip.io/k3s | vipAddress="${RKE2_VIP_IP}" vipInterface="${VIP_INTERFACE}" sh \
  | sudo tee /var/lib/rancher/rke2/server/manifests/vip.yaml > /dev/null

# Replace k3s references with rke2
sed -i 's/k3s/rke2/g' /var/lib/rancher/rke2/server/manifests/vip.yaml
echo "kube-vip manifest written to /var/lib/rancher/rke2/server/manifests/vip.yaml"

# ----------------------------------------------------------
# 3. Create RKE2 config with TLS SANs
# ----------------------------------------------------------
echo "=== Writing RKE2 config ==="
mkdir -p /etc/rancher/rke2
cat > /etc/rancher/rke2/config.yaml <<EOF
tls-san:
  - ${HOSTNAME}.${DOMAIN_SUFFIX}
  - ${HOSTNAME}
  - rke2master.${DOMAIN_SUFFIX}
  - rke2master
  - ${RKE2_VIP_IP}
write-kubeconfig-mode: "0644"
EOF
echo "RKE2 config written to /etc/rancher/rke2/config.yaml"

# ----------------------------------------------------------
# 4. Install k9s (ncurses-based Kubernetes dashboard)
# ----------------------------------------------------------
echo "=== Installing k9s ==="
wget -q "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" -O /tmp/k9s.tgz
tar zxf /tmp/k9s.tgz -C /tmp
chmod +x /tmp/k9s
mv /tmp/k9s /usr/local/bin/
rm -f /tmp/k9s.tgz
echo "k9s ${K9S_VERSION} installed to /usr/local/bin/k9s"

# ----------------------------------------------------------
# 5. Configure shell environment for RKE2
# ----------------------------------------------------------
echo "=== Configuring shell environment ==="
{
  echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml'
  echo 'export PATH=${PATH}:/var/lib/rancher/rke2/bin'
  echo 'alias k=kubectl'
} >> ~/.bash_profile
source ~/.bash_profile

echo "=== Pre-install complete ==="
echo "Next step: run bootstrap-primary.sh to install RKE2 and Rancher"
