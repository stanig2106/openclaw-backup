#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
source "$SCRIPT_DIR/s3-helper.sh"
load_env
check_s3_config

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="openclaw-backup-${TIMESTAMP}"
TMP_FILE="/tmp/${BACKUP_NAME}.tar.gz"
trap "rm -f $TMP_FILE 2>/dev/null" EXIT

[ -d "$DATA_DIR" ] || error "Répertoire de données introuvable: $DATA_DIR"

gateway_commit
WAS_RUNNING=false
gateway_stop && WAS_RUNNING=true

create_backup "$TMP_FILE"

[ "$WAS_RUNNING" = true ] && gateway_start

S3_DEST=$(s3_path "${BACKUP_NAME}.tar.gz")
BACKUP_SIZE=$(du -sh "$TMP_FILE" | cut -f1)
info "Upload vers S3: $S3_DEST ($BACKUP_SIZE)..."
s3 cp "$TMP_FILE" "$S3_DEST" --quiet

ok "Backup S3 complet terminé ! ($BACKUP_SIZE)"
echo ""
echo "  S3: $S3_DEST"
echo ""
