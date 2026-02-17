#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Charger la config
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

DATA_DIR="${OPENCLAW_DATA_DIR:-./data/config}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-./data/workspace}"
BACKUP_DIR="${1:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="openclaw-backup-${TIMESTAMP}"
IMAGE_NAME="${OPENCLAW_IMAGE:-openclaw:local}"

# Vérifier que les données existent
[ -d "$DATA_DIR" ] || error "Répertoire de données introuvable: $DATA_DIR"

# Créer le répertoire de backups
mkdir -p "$BACKUP_DIR"

# Commit du système (apt install, /opt, etc.) dans l'image
CONTAINER_NAME="openclaw-docker-openclaw-gateway-1"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
    info "Commit des modifications système du conteneur..."
    docker commit "$CONTAINER_NAME" "$IMAGE_NAME" >/dev/null
    ok "Snapshot système sauvegardé dans l'image"
fi

# Arrêter le gateway pour un backup cohérent
GATEWAY_RUNNING=false
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
    GATEWAY_RUNNING=true
    info "Arrêt temporaire du gateway..."
    docker stop "$CONTAINER_NAME" >/dev/null
fi

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

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
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
tar -czf "$BACKUP_FILE" -C "$TEMP_DIR" "$BACKUP_NAME"
BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)

# Redémarrer le gateway
if [ "$GATEWAY_RUNNING" = true ]; then
    info "Redémarrage du gateway..."
    docker start "$CONTAINER_NAME" >/dev/null
fi

ok "Backup complet terminé !"
echo ""
echo "  Fichier:  $BACKUP_FILE"
echo "  Taille:   $BACKUP_SIZE"
echo "  Contenu:"
echo "    - config/       (openclaw.json, tokens, sessions, auth)"
echo "    - workspace/    (code et artefacts de l'agent)"
echo "    - env.backup    (variables d'environnement)"
echo "    - image.tar.gz  (image Docker = systeme complet)"
echo ""
