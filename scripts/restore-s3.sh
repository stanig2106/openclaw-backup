#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
source "$SCRIPT_DIR/s3-helper.sh"
load_env
check_s3_config

# Lister les backups
info "Récupération de la liste des backups S3..."
BACKUP_LIST=$(list_s3_backups)
[ -n "$BACKUP_LIST" ] || error "Aucun backup trouvé sur S3"

# Afficher la liste numérotée
echo ""
echo -e "${CYAN}Backups disponibles :${NC}"
echo -e "${DIM}─────────────────────────────────────────────────────${NC}"

i=1
declare -a FILENAMES
while IFS= read -r line; do
    DATE=$(echo "$line" | awk '{print $1}')
    TIME=$(echo "$line" | awk '{print $2}')
    SIZE=$(echo "$line" | awk '{print $3}')
    FILE=$(echo "$line" | awk '{print $4}')
    FILENAMES+=("$FILE")

    # Taille lisible
    if [ "$SIZE" -gt 1073741824 ] 2>/dev/null; then
        HSIZE="$(echo "scale=1; $SIZE/1073741824" | bc)G"
    elif [ "$SIZE" -gt 1048576 ] 2>/dev/null; then
        HSIZE="$(echo "scale=1; $SIZE/1048576" | bc)M"
    elif [ "$SIZE" -gt 1024 ] 2>/dev/null; then
        HSIZE="$(echo "scale=1; $SIZE/1024" | bc)K"
    else
        HSIZE="${SIZE}B"
    fi

    if [ "$i" -eq 1 ]; then
        echo -e "  ${GREEN}[$i]${NC} $DATE $TIME  ${HSIZE}\t$FILE ${GREEN}(le plus récent)${NC}"
    else
        echo -e "  ${BLUE}[$i]${NC} $DATE $TIME  ${HSIZE}\t$FILE"
    fi
    i=$((i + 1))
done <<< "$BACKUP_LIST"

TOTAL=$((i - 1))
echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
echo ""

# Choix
read -p "Quel backup restaurer ? [1-$TOTAL] : " CHOICE
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "$TOTAL" ]; then
    error "Choix invalide"
fi

SELECTED_FILE="${FILENAMES[$((CHOICE - 1))]}"
S3_SRC=$(s3_path "$SELECTED_FILE")
info "Backup sélectionné: $SELECTED_FILE"

# Télécharger
TMP_FILE="/tmp/$SELECTED_FILE"
trap "rm -f $TMP_FILE 2>/dev/null" EXIT

info "Téléchargement depuis S3..."
s3 cp "$S3_SRC" "$TMP_FILE" --quiet

# Arrêter le gateway et restaurer
gateway_stop || true
restore_from "$TMP_FILE"
