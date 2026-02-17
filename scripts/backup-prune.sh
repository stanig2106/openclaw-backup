#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
source "$SCRIPT_DIR/s3-helper.sh"
load_env
check_s3_config

MAX_KEEP="${1:-3}"

info "Nettoyage S3 (on garde les $MAX_KEEP plus récents)..."

BACKUP_FILES=()
while IFS= read -r line; do
    FILE=$(echo "$line" | awk '{print $4}')
    [ -n "$FILE" ] && BACKUP_FILES+=("$FILE")
done <<< "$(list_s3_backups)"

TOTAL=${#BACKUP_FILES[@]}

if [ "$TOTAL" -le "$MAX_KEEP" ]; then
    info "$TOTAL backup(s), rien à supprimer."
    exit 0
fi

DELETED=0
for i in $(seq $((MAX_KEEP + 1)) "$TOTAL"); do
    FILE="${BACKUP_FILES[$((i - 1))]}"
    echo -e "  ${RED}[suppr.]${NC}  $FILE"
    s3 rm "$(s3_path "$FILE")" --quiet
    DELETED=$((DELETED + 1))
done

ok "$MAX_KEEP gardé(s), $DELETED supprimé(s)"
