#!/usr/bin/env bash
# templates/server-setup.sh — starter for a non-interactive server script.
#
# Conventions: AGENTS.md → "Execution Modes & Error Handling".
# Non-interactive scripts DO use strict mode and a trap.

set -euo pipefail
trap 'echo "Error at line $LINENO" >&2' ERR

# ── Config (UPPER_SNAKE_CASE) ────────────────────────────────────────
SERVICE_NAME="my-service"
WORK_DIR="/opt/$SERVICE_NAME"

# ── Helpers ──────────────────────────────────────────────────────────
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ── Preconditions ────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0"
command -v systemctl >/dev/null || die "systemd is required"

# ── Steps ────────────────────────────────────────────────────────────
log "Creating $WORK_DIR"
mkdir -p "$WORK_DIR"

log "Writing systemd unit"
cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=$SERVICE_NAME
After=network.target

[Service]
ExecStart=$WORK_DIR/run
Restart=always

[Install]
WantedBy=multi-user.target
EOF

log "Enabling $SERVICE_NAME"
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

log "Done. Logs: journalctl -u $SERVICE_NAME -f"
