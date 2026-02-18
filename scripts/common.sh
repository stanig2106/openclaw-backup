#!/usr/bin/env bash
# Fonctions partagées par tous les scripts OpenClaw

set -euo pipefail

# --- Initialisation ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# --- Couleurs ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# --- Logging ---
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Validation instance ---
validate_instance_name() {
    local name="$1"
    if [ ${#name} -gt 32 ]; then
        error "Le nom d'instance ne peut pas dépasser 32 caractères: '$name'"
    fi
    if ! [[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        error "Nom d'instance invalide: '$name' (minuscules, chiffres, tirets, ne commence/finit pas par un tiret)"
    fi
}

# --- Variables communes ---
load_env() {
    [ -f "$PROJECT_DIR/.env" ] || error "Fichier .env introuvable"
    set -a; source "$PROJECT_DIR/.env"; set +a

    # Instance
    INSTANCE_NAME="${INSTANCE_NAME:-main}"
    validate_instance_name "$INSTANCE_NAME"
    export COMPOSE_PROJECT_NAME="openclaw-${INSTANCE_NAME}"

    # Conteneur
    CONTAINER_NAME="openclaw-${INSTANCE_NAME}-gateway"

    # Chemins (defaults dynamiques basés sur l'instance)
    DATA_DIR="${OPENCLAW_DATA_DIR:-./data/${INSTANCE_NAME}/config}"
    WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-./data/${INSTANCE_NAME}/workspace}"
    BACKUP_DIR="./backups/${INSTANCE_NAME}"
    LOG_DIR="./logs/${INSTANCE_NAME}"
    IMAGE_NAME="${OPENCLAW_IMAGE:-openclaw:local}"
}

# --- Gateway ---
gateway_is_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"
}

gateway_commit() {
    if gateway_is_running; then
        info "Commit des modifications système du conteneur..."
        docker commit "$CONTAINER_NAME" "$IMAGE_NAME" >/dev/null
        ok "Snapshot système sauvegardé dans l'image"
    fi
}

gateway_stop() {
    if gateway_is_running; then
        info "Arrêt temporaire du gateway..."
        docker stop "$CONTAINER_NAME" >/dev/null
        return 0
    fi
    return 1
}

gateway_start() {
    info "Démarrage du gateway..."
    docker start "$CONTAINER_NAME" >/dev/null
}

gateway_up() {
    info "Démarrage du gateway..."
    docker compose up -d gateway
    ok "Gateway démarré !"
}

# --- Backup ---
create_backup() {
    local output_file="$1"
    local temp_dir
    temp_dir=$(mktemp -d "/tmp/openclaw-${INSTANCE_NAME}-backup.XXXXXX")

    mkdir -p "$temp_dir/$BACKUP_NAME"

    info "Sauvegarde des données..."
    cp -r "$DATA_DIR" "$temp_dir/$BACKUP_NAME/config"
    cp -r "$WORKSPACE_DIR" "$temp_dir/$BACKUP_NAME/workspace"
    [ -f "$PROJECT_DIR/.env" ] && cp "$PROJECT_DIR/.env" "$temp_dir/$BACKUP_NAME/env.backup"

    info "Export de l'image Docker ($IMAGE_NAME)... (peut prendre un moment)"
    docker save "$IMAGE_NAME" | gzip > "$temp_dir/$BACKUP_NAME/image.tar.gz"
    ok "Image Docker exportée"

    info "Création de l'archive..."
    tar -czf "$output_file" -C "$temp_dir" "$BACKUP_NAME"
    rm -rf "$temp_dir"
}

# --- Restore ---
restore_from() {
    local archive="$1"

    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    info "Extraction du backup..."
    tar -xzf "$archive" -C "$temp_dir"

    local extracted
    extracted=$(find "$temp_dir" -maxdepth 1 -type d -name "openclaw-*-backup-*" -o -name "openclaw-backup-*" | head -1)
    [ -n "$extracted" ] || error "Format de backup invalide"

    echo ""
    warn "Cette opération va REMPLACER les données actuelles !"
    read -p "Continuer ? (y/N) " -n 1 -r
    echo ""
    [[ $REPLY =~ ^[Yy]$ ]] || { info "Annulé."; exit 0; }

    # Sauvegarde de sécurité
    if [ -d "$DATA_DIR" ] && [ "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
        local safety="./backups/${INSTANCE_NAME}/pre-restore-$(date +%Y%m%d_%H%M%S).tar.gz"
        mkdir -p "./backups/${INSTANCE_NAME}"
        info "Sauvegarde de sécurité dans $safety..."
        tar -czf "$safety" "$DATA_DIR" "$WORKSPACE_DIR" 2>/dev/null || true
    fi

    # Données
    info "Restauration des données..."
    rm -rf "$DATA_DIR" "$WORKSPACE_DIR"
    mkdir -p "$DATA_DIR" "$WORKSPACE_DIR"
    cp -r "$extracted/config/." "$DATA_DIR/"
    cp -r "$extracted/workspace/." "$WORKSPACE_DIR/"

    # Image Docker
    if [ -f "$extracted/image.tar.gz" ]; then
        info "Restauration de l'image Docker... (peut prendre un moment)"
        gunzip -c "$extracted/image.tar.gz" | docker load
        ok "Image Docker restaurée"
    fi

    # .env
    if [ -f "$extracted/env.backup" ]; then
        echo ""
        read -p "Restaurer aussi le fichier .env ? (y/N) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp "$extracted/env.backup" "$PROJECT_DIR/.env"
            ok ".env restauré"
        fi
    fi

    # Permissions Linux
    if [[ "$OSTYPE" == "linux"* ]] && [ "$(id -u)" -eq 0 ]; then
        chown -R 1000:1000 "$DATA_DIR" "$WORKSPACE_DIR"
    fi

    ok "Restauration complète terminée !"
    gateway_up
}
