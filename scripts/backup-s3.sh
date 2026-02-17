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
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="openclaw-backup-${TIMESTAMP}"
IMAGE_NAME="${OPENCLAW_IMAGE:-openclaw:local}"
TMP_FILE="/tmp/${BACKUP_NAME}.tar.gz"

[ -d "$DATA_DIR" ] || error "Répertoire de données introuvable: $DATA_DIR"

# Commit du système (apt install, /opt, etc.) dans l'image
CONTAINER_NAME="openclaw-docker-openclaw-gateway-1"
GATEWAY_RUNNING=false
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
    info "Commit des modifications système du conteneur..."
    docker commit "$CONTAINER_NAME" "$IMAGE_NAME" >/dev/null
    ok "Snapshot système sauvegardé dans l'image"
    GATEWAY_RUNNING=true
    info "Arrêt temporaire du gateway..."
    docker stop "$CONTAINER_NAME" >/dev/null
fi

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR $TMP_FILE 2>/dev/null" EXIT

mkdir -p "$TEMP_DIR/$BACKUP_NAME"

# 1. Données (config + workspace + .env)
info "Sauvegarde des données..."
cp -r "$DATA_DIR" "$TEMP_DIR/$BACKUP_NAME/config"
cp -r "$WORKSPACE_DIR" "$TEMP_DIR/$BACKUP_NAME/workspace"
[ -f "$PROJECT_DIR/.env" ] && cp "$PROJECT_DIR/.env" "$TEMP_DIR/$BACKUP_NAME/env.backup"

# 2. Image Docker (système complet)
info "Export de l'image Docker ($IMAGE_NAME)... (peut prendre un moment)"
docker save "$IMAGE_NAME" | gzip > "$TEMP_DIR/$BACKUP_NAME/image.tar.gz"
ok "Image Docker exportée"

# 3. Archive finale
info "Création de l'archive..."
tar -czf "$TMP_FILE" -C "$TEMP_DIR" "$BACKUP_NAME"
BACKUP_SIZE=$(du -sh "$TMP_FILE" | cut -f1)

# Redémarrer le gateway
if [ "$GATEWAY_RUNNING" = true ]; then
    info "Redémarrage du gateway..."
    docker start "$CONTAINER_NAME" >/dev/null
fi

# Push vers S3
S3_DEST=$(s3_path "${BACKUP_NAME}.tar.gz")
info "Upload vers S3: $S3_DEST ($BACKUP_SIZE)..."
s3 cp "$TMP_FILE" "$S3_DEST" --quiet

ok "Backup S3 complet terminé !"
echo ""
echo "  Fichier:  ${BACKUP_NAME}.tar.gz"
echo "  Taille:   $BACKUP_SIZE"
echo "  S3:       $S3_DEST"
echo "  Contenu:"
echo "    - config/       (openclaw.json, tokens, sessions, auth)"
echo "    - workspace/    (code et artefacts de l'agent)"
echo "    - env.backup    (variables d'environnement)"
echo "    - image.tar.gz  (image Docker = systeme complet)"
echo ""
