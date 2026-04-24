#!/usr/bin/env bash
# Post-build rotation for RHEL gold templates.
#
# Only runs if Packer completed successfully (packer wires shell-local post-
# processors to fire on success). On failure, nothing changes — the existing
# CURRENT_TEMPLATE_NAME remains the working gold.
#
# End state:
#   PREVIOUS_TEMPLATE_NAME   = what CURRENT was before this build
#   CURRENT_TEMPLATE_NAME    = this build's template
#   (old previous is deleted)
#
# Required env vars (set by the Packer shell-local post-processor):
#   GOVC_URL, GOVC_USERNAME, GOVC_PASSWORD, GOVC_INSECURE, GOVC_DATACENTER
#   BUILD_TEMPLATE_NAME, CURRENT_TEMPLATE_NAME, PREVIOUS_TEMPLATE_NAME
#   TEMPLATE_FOLDER (may be empty)
#   GOVC_BIN (path to govc binary)

set -euo pipefail

: "${GOVC_URL:?}"
: "${GOVC_USERNAME:?}"
: "${GOVC_PASSWORD:?}"
: "${GOVC_DATACENTER:?}"
: "${BUILD_TEMPLATE_NAME:?}"
: "${CURRENT_TEMPLATE_NAME:?}"
: "${PREVIOUS_TEMPLATE_NAME:?}"
GOVC="${GOVC_BIN:-govc}"
export GOVC_URL GOVC_USERNAME GOVC_PASSWORD GOVC_INSECURE GOVC_DATACENTER

log() { printf '[rotate-templates] %s\n' "$*" >&2; }

if ! command -v "$GOVC" >/dev/null 2>&1; then
  log "ERROR: govc not found (set GOVC_BIN or install from https://github.com/vmware/govmomi/releases)"
  exit 1
fi

# Helpers -------------------------------------------------------------------

# Full inventory path for a template name. Returns empty string if not found.
resolve_path() {
  local name="$1"
  if [ -n "${TEMPLATE_FOLDER:-}" ]; then
    local candidate="/${GOVC_DATACENTER}/vm/${TEMPLATE_FOLDER%/}/${name}"
    if "$GOVC" vm.info -vm.ipath "$candidate" >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  fi
  # Fallback: search the datacenter
  "$GOVC" find "/${GOVC_DATACENTER}/vm" -type m -name "$name" 2>/dev/null | head -n1
}

exists() {
  [ -n "$(resolve_path "$1")" ]
}

# Rotation ------------------------------------------------------------------

log "Build template:    $BUILD_TEMPLATE_NAME"
log "Target (current):  $CURRENT_TEMPLATE_NAME"
log "Target (previous): $PREVIOUS_TEMPLATE_NAME"

build_path="$(resolve_path "$BUILD_TEMPLATE_NAME")"
if [ -z "$build_path" ]; then
  log "ERROR: build template '$BUILD_TEMPLATE_NAME' not found — aborting rotation"
  exit 1
fi

# 1. Delete existing PREVIOUS (if present)
if exists "$PREVIOUS_TEMPLATE_NAME"; then
  prev_path="$(resolve_path "$PREVIOUS_TEMPLATE_NAME")"
  log "Deleting old previous: $prev_path"
  "$GOVC" vm.markasvm -vm "$prev_path" >/dev/null 2>&1 || true
  "$GOVC" vm.destroy -vm "$prev_path"
else
  log "No existing '$PREVIOUS_TEMPLATE_NAME' to delete — skipping"
fi

# 2. Rename current CURRENT → PREVIOUS (if present and different from the build)
if exists "$CURRENT_TEMPLATE_NAME"; then
  cur_path="$(resolve_path "$CURRENT_TEMPLATE_NAME")"
  if [ "$cur_path" = "$build_path" ]; then
    log "Current template already points at the new build — skipping rename-to-previous"
  else
    log "Renaming current → previous: $cur_path → $PREVIOUS_TEMPLATE_NAME"
    "$GOVC" object.rename "$cur_path" "$PREVIOUS_TEMPLATE_NAME"
  fi
else
  log "No existing '$CURRENT_TEMPLATE_NAME' — first run, nothing to rotate out"
fi

# 3. Rename BUILD → CURRENT
log "Renaming build → current: $build_path → $CURRENT_TEMPLATE_NAME"
"$GOVC" object.rename "$build_path" "$CURRENT_TEMPLATE_NAME"

log "Rotation complete."
