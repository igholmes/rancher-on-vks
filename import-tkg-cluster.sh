#!/bin/bash
set -euo pipefail

# ============================================================
# Import a VKS TKG (Tanzu Kubernetes Grid) cluster into Rancher
#
# Prerequisites:
#   - kubectl access to the Rancher management cluster
#   - kubectl access to the TKG workload cluster to be imported
#   - Rancher API URL and bearer token
# ============================================================

LOG_FILE="/var/log/import-tkg-cluster.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ----------------------------------------------------------
# Prompt for configuration
# ----------------------------------------------------------
read -rp "Enter the Rancher URL (e.g. https://rancher.example.com): " RANCHER_URL
read -rp "Enter the Rancher API bearer token: " RANCHER_TOKEN
read -rp "Enter a name for the imported cluster: " CLUSTER_NAME
read -rp "Enter the path to the TKG cluster kubeconfig: " TKG_KUBECONFIG

if [[ ! -f "$TKG_KUBECONFIG" ]]; then
  echo "ERROR: Kubeconfig not found at ${TKG_KUBECONFIG}"
  exit 1
fi

echo ""
echo "=== Import Settings ==="
echo "Rancher URL:    ${RANCHER_URL}"
echo "Cluster Name:   ${CLUSTER_NAME}"
echo "TKG Kubeconfig: ${TKG_KUBECONFIG}"
echo ""
read -rp "Proceed? [Y/n]: " confirm
if [[ "${confirm,,}" == "n" ]]; then
  echo "Aborted."
  exit 1
fi

# ----------------------------------------------------------
# 1. Create the cluster object in Rancher via API
# ----------------------------------------------------------
echo "=== Creating cluster in Rancher ==="
CLUSTER_RESPONSE=$(curl -sk "${RANCHER_URL}/v3/clusters" \
  -H "Authorization: Bearer ${RANCHER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"cluster\",
    \"name\": \"${CLUSTER_NAME}\",
    \"description\": \"TKG cluster imported from VKS\",
    \"dockerRootDir\": \"/var/lib/docker\",
    \"enableNetworkPolicy\": true
  }")

CLUSTER_ID=$(echo "$CLUSTER_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
if [[ -z "$CLUSTER_ID" ]]; then
  echo "ERROR: Failed to create cluster in Rancher. Response:"
  echo "$CLUSTER_RESPONSE"
  exit 1
fi
echo "Cluster created with ID: ${CLUSTER_ID}"

# ----------------------------------------------------------
# 2. Retrieve the cluster registration token and manifest URL
# ----------------------------------------------------------
echo "=== Generating registration token ==="
REG_RESPONSE=$(curl -sk "${RANCHER_URL}/v3/clusters/${CLUSTER_ID}/clusterregistrationtokens" \
  -H "Authorization: Bearer ${RANCHER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"type\": \"clusterRegistrationToken\", \"clusterId\": \"${CLUSTER_ID}\"}")

MANIFEST_URL=$(echo "$REG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['manifestUrl'])" 2>/dev/null)
if [[ -z "$MANIFEST_URL" ]]; then
  echo "ERROR: Failed to get registration token. Response:"
  echo "$REG_RESPONSE"
  exit 1
fi
echo "Manifest URL: ${MANIFEST_URL}"

# ----------------------------------------------------------
# 3. Apply the Rancher agent manifest to the TKG cluster
# ----------------------------------------------------------
echo "=== Applying Rancher agent to TKG cluster ==="
curl -sfL "${MANIFEST_URL}" | kubectl --kubeconfig="${TKG_KUBECONFIG}" apply -f -

# ----------------------------------------------------------
# 4. Wait for the cluster to become active in Rancher
# ----------------------------------------------------------
echo "=== Waiting for cluster to become Active ==="
MAX_WAIT=300
ELAPSED=0
while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  STATE=$(curl -sk "${RANCHER_URL}/v3/clusters/${CLUSTER_ID}" \
    -H "Authorization: Bearer ${RANCHER_TOKEN}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('state',''))" 2>/dev/null)

  echo "  Cluster state: ${STATE} (${ELAPSED}s elapsed)"
  if [[ "$STATE" == "active" ]]; then
    break
  fi
  sleep 15
  ELAPSED=$((ELAPSED + 15))
done

if [[ "$STATE" != "active" ]]; then
  echo "WARNING: Cluster did not reach Active state within ${MAX_WAIT}s."
  echo "Check Rancher UI at ${RANCHER_URL} for status."
  exit 1
fi

# ----------------------------------------------------------
# 5. Verify imported cluster
# ----------------------------------------------------------
echo "=== Verifying import ==="
curl -sk "${RANCHER_URL}/v3/clusters/${CLUSTER_ID}" \
  -H "Authorization: Bearer ${RANCHER_TOKEN}" \
  | python3 -c "
import sys, json
c = json.load(sys.stdin)
print(f\"  Name:       {c['name']}\")
print(f\"  State:      {c['state']}\")
print(f\"  Provider:   {c.get('provider','N/A')}\")
print(f\"  K8s:        {c.get('version',{}).get('gitVersion','N/A')}\")
print(f\"  Nodes:      {c.get('nodeCount','N/A')}\")
"

echo ""
echo "=== Import complete ==="
echo "Cluster '${CLUSTER_NAME}' (${CLUSTER_ID}) is now managed by Rancher."
echo "View at: ${RANCHER_URL}/dashboard/c/${CLUSTER_ID}/explorer"
