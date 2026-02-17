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

# Vérifier l'argument
BACKUP_FILE="${1:-}"
[ -n "$BACKUP_FILE" ] || error "Usage: $0 <chemin-vers-backup.tar.gz>"
[ -f "$BACKUP_FILE" ] || error "Fichier introuvable: $BACKUP_FILE"

# Charger la config
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

DATA_DIR="${OPENCLAW_DATA_DIR:-./data/config}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-./data/workspace}"

# Arrêter le gateway s'il tourne
if docker compose ps openclaw-gateway --format json 2>/dev/null | grep -q '"running"'; then
    info "Arrêt du gateway..."
    docker compose stop openclaw-gateway
fi

# Extraire dans un répertoire temporaire
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

info "Extraction du backup..."
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

# Trouver le répertoire extrait
EXTRACTED_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "openclaw-backup-*" | head -1)
[ -n "$EXTRACTED_DIR" ] || error "Format de backup invalide"

# Confirmation
echo ""
warn "Cette opération va REMPLACER les données actuelles !"
echo "  Config:    $DATA_DIR"
echo "  Workspace: $WORKSPACE_DIR"
echo ""
read -p "Continuer ? (y/N) " -n 1 -r
echo ""
[[ $REPLY =~ ^[Yy]$ ]] || { info "Annulé."; exit 0; }

# Sauvegarder les données actuelles (au cas où)
if [ -d "$DATA_DIR" ] && [ "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
    SAFETY_BACKUP="./backups/pre-restore-$(date +%Y%m%d_%H%M%S).tar.gz"
    mkdir -p ./backups
    info "Sauvegarde de sécurité des données actuelles dans $SAFETY_BACKUP..."
    tar -czf "$SAFETY_BACKUP" "$DATA_DIR" "$WORKSPACE_DIR" 2>/dev/null || true
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

# Restaurer le .env si présent et si l'utilisateur le veut
if [ -f "$EXTRACTED_DIR/env.backup" ]; then
    echo ""
    read -p "Restaurer aussi le fichier .env depuis le backup ? (y/N) " -n 1 -r
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
echo ""
echo "  Redémarre le gateway: task start"
echo ""
