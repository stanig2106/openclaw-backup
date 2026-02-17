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

[ -d "$PROJECT_DIR/openclaw" ] || error "Repo OpenClaw introuvable. Lance d'abord: task setup"

CONTAINER_NAME="openclaw-docker-openclaw-gateway-1"

# Commit des modifs système avant mise à jour
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    info "Commit des modifications système du conteneur..."
    docker commit "$CONTAINER_NAME" "${OPENCLAW_IMAGE:-openclaw:local}-pre-update" || warn "Commit échoué"
    ok "Snapshot système sauvegardé dans l'image -pre-update"
fi

# Backup automatique avant mise à jour
info "Backup avant mise à jour..."
bash "$SCRIPT_DIR/backup.sh" || warn "Backup échoué, on continue quand même"

# Mise à jour du code source
info "Mise à jour du code source OpenClaw..."
cd "$PROJECT_DIR/openclaw"
git fetch origin
git pull --ff-only || error "Impossible de mettre à jour (conflits ?). Résous manuellement dans ./openclaw/"
cd "$PROJECT_DIR"
ok "Code source mis à jour"

# Rebuild de l'image (2 étapes)
info "Reconstruction de l'image de base..."
docker build -t openclaw:base --no-cache \
    -f "$PROJECT_DIR/openclaw/Dockerfile" \
    "$PROJECT_DIR/openclaw"
ok "Image de base reconstruite"

info "Reconstruction de l'image finale avec les outils..."
docker compose build --no-cache openclaw-gateway
ok "Image finale reconstruite"

# Redémarrage
info "Redémarrage du gateway..."
docker compose down openclaw-gateway
docker compose up -d openclaw-gateway
ok "Gateway redémarré avec la nouvelle version"

echo ""
echo "  Vérifie les logs: task logs"
echo "  Vérifie le statut: task status"
echo ""
