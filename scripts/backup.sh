#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
load_env

BACKUP_DIR="${1:-./backups/${INSTANCE_NAME}}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="openclaw-${INSTANCE_NAME}-backup-${TIMESTAMP}"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

[ -d "$DATA_DIR" ] || error "Répertoire de données introuvable: $DATA_DIR"
mkdir -p "$BACKUP_DIR"

gateway_commit
WAS_RUNNING=false
gateway_stop && WAS_RUNNING=true

create_backup "$BACKUP_FILE"

[ "$WAS_RUNNING" = true ] && gateway_start

BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
ok "Backup complet terminé ! ($BACKUP_SIZE)"
echo ""
echo "  Fichier: $BACKUP_FILE"
echo ""
