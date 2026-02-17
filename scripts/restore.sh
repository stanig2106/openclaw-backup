#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
load_env

BACKUP_FILE="${1:-}"
[ -n "$BACKUP_FILE" ] || error "Usage: restore.sh <chemin-vers-backup.tar.gz>"
[ -f "$BACKUP_FILE" ] || error "Fichier introuvable: $BACKUP_FILE"

gateway_stop || true
restore_from "$BACKUP_FILE"
