#!/usr/bin/env bash
# Migration d'une installation single-instance vers le layout multi-instance
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

# Charger le .env sans valider l'instance (elle n'existe peut-être pas encore)
[ -f "$PROJECT_DIR/.env" ] || error "Fichier .env introuvable"
set -a; source "$PROJECT_DIR/.env"; set +a
IMAGE_NAME="${OPENCLAW_IMAGE:-openclaw:local}"

# Déterminer le nom d'instance cible
INSTANCE="${INSTANCE_NAME:-main}"
echo ""
echo -e "${BLUE}Migration vers le layout multi-instance${NC}"
echo ""
read -p "Nom de l'instance cible [$INSTANCE] : " INPUT
INSTANCE="${INPUT:-$INSTANCE}"
validate_instance_name "$INSTANCE"

OLD_CONTAINER="openclaw-docker-openclaw-gateway-1"
OLD_DATA="./data/config"
OLD_WORKSPACE="./data/workspace"
OLD_VOLUME="openclaw_home"

NEW_DATA="./data/${INSTANCE}/config"
NEW_WORKSPACE="./data/${INSTANCE}/workspace"
NEW_VOLUME="openclaw_${INSTANCE}_home"
NEW_BACKUP="./backups/${INSTANCE}"
NEW_LOG="./logs/${INSTANCE}"

# Vérifier qu'il y a quelque chose à migrer
HAS_WORK=false
[ -d "$OLD_DATA" ] && HAS_WORK=true
[ -d "$OLD_WORKSPACE" ] && HAS_WORK=true
[ -d "./backups" ] && ls ./backups/*.tar.gz >/dev/null 2>&1 && HAS_WORK=true
docker volume inspect "$OLD_VOLUME" >/dev/null 2>&1 && HAS_WORK=true

if [ "$HAS_WORK" = false ]; then
    warn "Rien à migrer (pas d'ancien layout détecté)."
    exit 0
fi

echo ""
echo -e "${YELLOW}Cette migration va :${NC}"
[ -d "$OLD_DATA" ] && echo "  - Déplacer $OLD_DATA -> $NEW_DATA"
[ -d "$OLD_WORKSPACE" ] && echo "  - Déplacer $OLD_WORKSPACE -> $NEW_WORKSPACE"
ls ./backups/*.tar.gz >/dev/null 2>&1 && echo "  - Déplacer ./backups/*.tar.gz -> $NEW_BACKUP/"
ls ./logs/*.log >/dev/null 2>&1 && echo "  - Déplacer ./logs/*.log -> $NEW_LOG/"
docker volume inspect "$OLD_VOLUME" >/dev/null 2>&1 && echo "  - Renommer le volume $OLD_VOLUME -> $NEW_VOLUME"
docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${OLD_CONTAINER}$" && echo "  - Supprimer l'ancien container $OLD_CONTAINER"
echo ""

read -p "Continuer ? (y/N) " -n 1 -r
echo ""
[[ $REPLY =~ ^[Yy]$ ]] || { info "Annulé."; exit 0; }

# 1. Arrêter l'ancien container
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${OLD_CONTAINER}$"; then
    info "Arrêt de l'ancien container..."
    docker stop "$OLD_CONTAINER" >/dev/null
fi

# 2. Déplacer les données
if [ -d "$OLD_DATA" ]; then
    info "Déplacement des données config..."
    mkdir -p "$(dirname "$NEW_DATA")"
    mv "$OLD_DATA" "$NEW_DATA"
    ok "Config déplacée vers $NEW_DATA"
fi

if [ -d "$OLD_WORKSPACE" ]; then
    info "Déplacement du workspace..."
    mkdir -p "$(dirname "$NEW_WORKSPACE")"
    mv "$OLD_WORKSPACE" "$NEW_WORKSPACE"
    ok "Workspace déplacé vers $NEW_WORKSPACE"
fi

# Nettoyer l'ancien répertoire data s'il est vide
rmdir ./data/config 2>/dev/null || true
rmdir ./data/workspace 2>/dev/null || true

# 3. Déplacer les backups
if ls ./backups/*.tar.gz >/dev/null 2>&1; then
    info "Déplacement des backups..."
    mkdir -p "$NEW_BACKUP"
    mv ./backups/*.tar.gz "$NEW_BACKUP/" 2>/dev/null || true
    ok "Backups déplacés vers $NEW_BACKUP/"
fi

# 4. Déplacer les logs
if ls ./logs/*.log >/dev/null 2>&1; then
    info "Déplacement des logs..."
    mkdir -p "$NEW_LOG"
    mv ./logs/*.log "$NEW_LOG/" 2>/dev/null || true
    ok "Logs déplacés vers $NEW_LOG/"
fi

# 5. Renommer le volume Docker
if docker volume inspect "$OLD_VOLUME" >/dev/null 2>&1; then
    if docker volume inspect "$NEW_VOLUME" >/dev/null 2>&1; then
        warn "Le volume $NEW_VOLUME existe déjà, on garde l'ancien tel quel"
    else
        info "Renommage du volume Docker $OLD_VOLUME -> $NEW_VOLUME..."
        # Docker ne supporte pas le rename, on copie via un container temporaire
        docker volume create "$NEW_VOLUME" >/dev/null
        docker run --rm \
            -v "${OLD_VOLUME}:/from" \
            -v "${NEW_VOLUME}:/to" \
            alpine sh -c "cp -a /from/. /to/"
        docker volume rm "$OLD_VOLUME" >/dev/null 2>&1 || warn "Impossible de supprimer l'ancien volume $OLD_VOLUME"
        ok "Volume renommé"
    fi
fi

# 6. Supprimer l'ancien container
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${OLD_CONTAINER}$"; then
    info "Suppression de l'ancien container..."
    docker rm "$OLD_CONTAINER" >/dev/null
    ok "Ancien container supprimé"
fi

# 7. Mettre à jour le .env
if ! grep -q "^INSTANCE_NAME=" "$PROJECT_DIR/.env"; then
    # Ajouter INSTANCE_NAME après le header
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "1,/^$/{ /^$/a\\
INSTANCE_NAME=${INSTANCE}
}" "$PROJECT_DIR/.env"
    else
        sed -i "1,/^$/{ /^$/a INSTANCE_NAME=${INSTANCE}" "$PROJECT_DIR/.env"
    fi
else
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^INSTANCE_NAME=.*/INSTANCE_NAME=${INSTANCE}/" "$PROJECT_DIR/.env"
    else
        sed -i "s/^INSTANCE_NAME=.*/INSTANCE_NAME=${INSTANCE}/" "$PROJECT_DIR/.env"
    fi
fi
ok "INSTANCE_NAME=${INSTANCE} dans .env"

# 8. Mettre à jour le cron marker
OLD_CRON_MARKER="# openclaw-backup"
NEW_CRON_MARKER="# openclaw-backup-${INSTANCE}"
if crontab -l 2>/dev/null | grep -q "$OLD_CRON_MARKER"; then
    info "Mise à jour du cron marker..."
    crontab -l 2>/dev/null | sed "s|${OLD_CRON_MARKER}$|${NEW_CRON_MARKER}|" | crontab -
    ok "Cron marker mis à jour"
fi

echo ""
ok "Migration terminée !"
echo ""
echo "  Instance:   $INSTANCE"
echo "  Config:     $NEW_DATA"
echo "  Workspace:  $NEW_WORKSPACE"
echo "  Backups:    $NEW_BACKUP"
echo "  Volume:     $NEW_VOLUME"
echo ""
echo "  Démarre avec: task start"
echo ""
