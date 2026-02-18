#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
source "$SCRIPT_DIR/s3-helper.sh"
load_env
check_s3_config

CRON_EXPR="30 3 * * *"
MAX_KEEP=3
CRON_MARKER="# openclaw-backup-${INSTANCE_NAME}"

CRON_CMD="cd $PROJECT_DIR && INSTANCE_NAME=${INSTANCE_NAME} $SCRIPT_DIR/backup-s3.sh >> $PROJECT_DIR/logs/${INSTANCE_NAME}/backup-cron.log 2>&1 && INSTANCE_NAME=${INSTANCE_NAME} $SCRIPT_DIR/backup-prune.sh $MAX_KEEP >> $PROJECT_DIR/logs/${INSTANCE_NAME}/backup-cron.log 2>&1"
CRON_LINE="$CRON_EXPR $CRON_CMD"

mkdir -p "$PROJECT_DIR/logs/${INSTANCE_NAME}"

EXISTING=$(crontab -l 2>/dev/null | grep -v "$CRON_MARKER" || true)
if [ -n "$EXISTING" ]; then
    echo "$EXISTING
$CRON_LINE $CRON_MARKER" | crontab -
else
    echo "$CRON_LINE $CRON_MARKER" | crontab -
fi

ok "Cron installé ! (instance: ${INSTANCE_NAME})"
echo ""
echo "  Planification:  tous les jours a 3h30"
echo "  Retention:      $MAX_KEEP backups max"
echo "  Logs:           $PROJECT_DIR/logs/${INSTANCE_NAME}/backup-cron.log"
echo ""
