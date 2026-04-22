#!/bin/bash
set -euo pipefail

# ============================================================
# etcd Backup and Restore Drill for RKE2 on VCF
#
# Supports two modes:
#   backup  - Snapshot etcd and store locally + optional remote
#   restore - Restore etcd from a snapshot on this node
#
# Usage:
#   ./etcd-backup-restore-rke2.sh backup
#   ./etcd-backup-restore-rke2.sh restore
# ============================================================

ETCDCTL="/var/lib/rancher/rke2/bin/etcdctl"
ETCD_DIR="/var/lib/rancher/rke2/server/db/etcd"
BACKUP_DIR="/opt/rke2-etcd-backups"
RKE2_SERVICE="rke2-server"
ETCD_CERT="/var/lib/rancher/rke2/server/tls/etcd/server-client.crt"
ETCD_KEY="/var/lib/rancher/rke2/server/tls/etcd/server-client.key"
ETCD_CACERT="/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt"

LOG_FILE="/var/log/etcd-backup-restore.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ----------------------------------------------------------
# Helper functions
# ----------------------------------------------------------
etcdctl_cmd() {
  "${ETCDCTL}" \
    --endpoints=https://127.0.0.1:2379 \
    --cert="${ETCD_CERT}" \
    --key="${ETCD_KEY}" \
    --cacert="${ETCD_CACERT}" \
    "$@"
}

check_etcd_health() {
  echo "=== Checking etcd health ==="
  etcdctl_cmd endpoint health
  etcdctl_cmd endpoint status --write-out=table
}

# ----------------------------------------------------------
# BACKUP
# ----------------------------------------------------------
do_backup() {
  read -rp "Enter remote backup destination (scp path, or leave empty to skip): " REMOTE_DEST

  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  SNAPSHOT_NAME="etcd-snapshot-${TIMESTAMP}.db"
  SNAPSHOT_PATH="${BACKUP_DIR}/${SNAPSHOT_NAME}"

  mkdir -p "${BACKUP_DIR}"

  echo ""
  echo "=== Backup Settings ==="
  echo "Snapshot: ${SNAPSHOT_PATH}"
  echo "Remote:   ${REMOTE_DEST:-none}"
  echo ""
  read -rp "Proceed with backup? [Y/n]: " confirm
  if [[ "${confirm,,}" == "n" ]]; then
    echo "Aborted."
    exit 1
  fi

  # Pre-backup health check
  check_etcd_health

  # Take the snapshot
  echo "=== Taking etcd snapshot ==="
  etcdctl_cmd snapshot save "${SNAPSHOT_PATH}"

  # Verify snapshot integrity
  echo "=== Verifying snapshot ==="
  etcdctl_cmd snapshot status "${SNAPSHOT_PATH}" --write-out=table

  SNAPSHOT_SIZE=$(du -h "${SNAPSHOT_PATH}" | cut -f1)
  echo "Snapshot saved: ${SNAPSHOT_PATH} (${SNAPSHOT_SIZE})"

  # Copy to remote if specified
  if [[ -n "${REMOTE_DEST}" ]]; then
    echo "=== Copying snapshot to remote ==="
    scp "${SNAPSHOT_PATH}" "${REMOTE_DEST}/${SNAPSHOT_NAME}"
    echo "Remote copy complete."
  fi

  # Prune old local backups (keep last 5)
  echo "=== Pruning old backups (keeping last 5) ==="
  ls -1t "${BACKUP_DIR}"/etcd-snapshot-*.db 2>/dev/null | tail -n +6 | xargs -r rm -v

  echo ""
  echo "=== Backup complete ==="
  echo "Local snapshots:"
  ls -lh "${BACKUP_DIR}"/etcd-snapshot-*.db
}

# ----------------------------------------------------------
# RESTORE
# ----------------------------------------------------------
do_restore() {
  echo "=== Available local snapshots ==="
  if ! ls "${BACKUP_DIR}"/etcd-snapshot-*.db 1>/dev/null 2>&1; then
    echo "No snapshots found in ${BACKUP_DIR}."
    read -rp "Enter full path to a snapshot file: " SNAPSHOT_PATH
  else
    ls -1t "${BACKUP_DIR}"/etcd-snapshot-*.db | nl -w2 -s'. '
    echo ""
    read -rp "Enter snapshot number to restore (or full path): " selection
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
      SNAPSHOT_PATH=$(ls -1t "${BACKUP_DIR}"/etcd-snapshot-*.db | sed -n "${selection}p")
    else
      SNAPSHOT_PATH="$selection"
    fi
  fi

  if [[ ! -f "$SNAPSHOT_PATH" ]]; then
    echo "ERROR: Snapshot not found at ${SNAPSHOT_PATH}"
    exit 1
  fi

  echo ""
  echo "=== Restore Settings ==="
  echo "Snapshot: ${SNAPSHOT_PATH}"
  echo ""
  echo "WARNING: This will stop RKE2, wipe the current etcd data, and restore from the snapshot."
  read -rp "Type 'RESTORE' to confirm: " confirm
  if [[ "$confirm" != "RESTORE" ]]; then
    echo "Aborted."
    exit 1
  fi

  # Pre-restore: verify snapshot
  echo "=== Verifying snapshot ==="
  etcdctl_cmd snapshot status "${SNAPSHOT_PATH}" --write-out=table

  # Stop RKE2
  echo "=== Stopping RKE2 ==="
  systemctl stop "${RKE2_SERVICE}"
  sleep 5

  # Backup current etcd data directory
  ETCD_BACKUP_DIR="${ETCD_DIR}.bak.$(date +%Y%m%d-%H%M%S)"
  echo "=== Backing up current etcd data to ${ETCD_BACKUP_DIR} ==="
  mv "${ETCD_DIR}" "${ETCD_BACKUP_DIR}"

  # Restore from snapshot
  echo "=== Restoring etcd from snapshot ==="
  "${ETCDCTL}" snapshot restore "${SNAPSHOT_PATH}" \
    --data-dir="${ETCD_DIR}"

  # Start RKE2
  echo "=== Starting RKE2 ==="
  systemctl start "${RKE2_SERVICE}"

  # Wait for RKE2 to come back
  echo "=== Waiting for RKE2 to be ready ==="
  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
  export PATH="${PATH}:/var/lib/rancher/rke2/bin"

  MAX_WAIT=180
  ELAPSED=0
  while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    if kubectl get nodes &>/dev/null; then
      echo "  RKE2 is responding (${ELAPSED}s)"
      break
    fi
    echo "  Waiting... (${ELAPSED}s)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
  done

  # Post-restore health check
  sleep 10
  check_etcd_health

  echo ""
  echo "=== Restore complete ==="
  echo "Previous etcd data saved at: ${ETCD_BACKUP_DIR}"
  kubectl get nodes
}

# ----------------------------------------------------------
# Main
# ----------------------------------------------------------
MODE="${1:-}"

case "$MODE" in
  backup)
    do_backup
    ;;
  restore)
    do_restore
    ;;
  health)
    check_etcd_health
    ;;
  *)
    echo "Usage: $0 {backup|restore|health}"
    echo ""
    echo "  backup  - Take an etcd snapshot and optionally copy to remote"
    echo "  restore - Restore etcd from a snapshot (stops/starts RKE2)"
    echo "  health  - Check etcd endpoint health and status"
    exit 1
    ;;
esac
