#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

source "$SCRIPT_DIR/s3-helper.sh"

# Charger la config
[ -f "$PROJECT_DIR/.env" ] || error "Fichier .env introuvable"
set -a; source "$PROJECT_DIR/.env"; set +a

check_s3_config

# Cron fixe : 3h30, garde 3 backups
CRON_EXPR="30 3 * * *"
MAX_KEEP=3

CRON_CMD="cd $PROJECT_DIR && $SCRIPT_DIR/backup-s3.sh >> $PROJECT_DIR/logs/backup-cron.log 2>&1 && $SCRIPT_DIR/backup-prune.sh $MAX_KEEP >> $PROJECT_DIR/logs/backup-cron.log 2>&1"
CRON_LINE="$CRON_EXPR $CRON_CMD"
CRON_MARKER="# openclaw-backup"

mkdir -p "$PROJECT_DIR/logs"

# Supprimer l'ancienne entrée si elle existe
EXISTING_CRONTAB=$(crontab -l 2>/dev/null || true)
NEW_CRONTAB=$(echo "$EXISTING_CRONTAB" | grep -v "$CRON_MARKER" || true)

if [ -n "$NEW_CRONTAB" ]; then
    NEW_CRONTAB="$NEW_CRONTAB
$CRON_LINE $CRON_MARKER"
else
    NEW_CRONTAB="$CRON_LINE $CRON_MARKER"
fi

echo "$NEW_CRONTAB" | crontab -

ok "Cron installé !"
echo ""
echo "  Planification:  tous les jours a 3h30"
echo "  Retention:      3 backups max"
echo "  Logs:           $PROJECT_DIR/logs/backup-cron.log"
echo ""
echo "  Verifier:       crontab -l | grep openclaw"
echo "  Supprimer:      task backup:cron:remove"
echo ""
