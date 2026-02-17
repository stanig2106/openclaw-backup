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

DATA_DIR="${OPENCLAW_DATA_DIR:-./data/config}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-./data/workspace}"

# Lister les backups
info "Récupération de la liste des backups S3..."
BACKUP_LIST=$(list_s3_backups)

if [ -z "$BACKUP_LIST" ]; then
    error "Aucun backup trouvé dans s3://${S3_BUCKET}/${S3_PREFIX:-openclaw-backups}/"
fi

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

# Choix de l'utilisateur
read -p "Quel backup restaurer ? [1-$TOTAL] : " CHOICE

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "$TOTAL" ]; then
    error "Choix invalide"
fi

SELECTED_FILE="${FILENAMES[$((CHOICE - 1))]}"
S3_SRC=$(s3_path "$SELECTED_FILE")

info "Backup sélectionné: $SELECTED_FILE"

# Arrêter le gateway s'il tourne
CONTAINER_NAME="openclaw-docker-openclaw-gateway-1"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
    info "Arrêt du gateway..."
    docker stop "$CONTAINER_NAME" >/dev/null
fi

# Télécharger depuis S3
TMP_FILE="/tmp/$SELECTED_FILE"
trap "rm -f $TMP_FILE 2>/dev/null" EXIT

info "Téléchargement depuis S3..."
s3 cp "$S3_SRC" "$TMP_FILE" --quiet

# Extraire
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR $TMP_FILE 2>/dev/null" EXIT

info "Extraction..."
tar -xzf "$TMP_FILE" -C "$TEMP_DIR"

EXTRACTED_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "openclaw-backup-*" | head -1)
[ -n "$EXTRACTED_DIR" ] || error "Format de backup invalide"

# Confirmation
echo ""
warn "Cette opération va REMPLACER les données actuelles !"
read -p "Continuer ? (y/N) " -n 1 -r
echo ""
[[ $REPLY =~ ^[Yy]$ ]] || { info "Annulé."; exit 0; }

# Sauvegarde de sécurité
if [ -d "$DATA_DIR" ] && [ "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
    SAFETY="./backups/pre-restore-$(date +%Y%m%d_%H%M%S).tar.gz"
    mkdir -p ./backups
    info "Sauvegarde de sécurité locale dans $SAFETY..."
    tar -czf "$SAFETY" "$DATA_DIR" "$WORKSPACE_DIR" 2>/dev/null || true
fi

# Restaurer les données
info "Restauration des données..."
rm -rf "$DATA_DIR" "$WORKSPACE_DIR"
mkdir -p "$DATA_DIR" "$WORKSPACE_DIR"
cp -r "$EXTRACTED_DIR/config/." "$DATA_DIR/"
cp -r "$EXTRACTED_DIR/workspace/." "$WORKSPACE_DIR/"

# Restaurer l'image Docker si présente
if [ -f "$EXTRACTED_DIR/image.tar.gz" ]; then
    info "Restauration de l'image Docker... (peut prendre un moment)"
    gunzip -c "$EXTRACTED_DIR/image.tar.gz" | docker load
    ok "Image Docker restaurée"
fi

# Restaurer le .env si présent
if [ -f "$EXTRACTED_DIR/env.backup" ]; then
    echo ""
    read -p "Restaurer aussi le fichier .env ? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp "$EXTRACTED_DIR/env.backup" "$PROJECT_DIR/.env"
        ok ".env restauré"
    fi
fi

# Permissions (Linux)
if [[ "$OSTYPE" == "linux"* ]] && [ "$(id -u)" -eq 0 ]; then
    chown -R 1000:1000 "$DATA_DIR" "$WORKSPACE_DIR"
fi

ok "Restauration complète terminée !"

# Démarrer le gateway
info "Démarrage du gateway..."
docker compose up -d openclaw-gateway
ok "Gateway démarré !"
echo ""
