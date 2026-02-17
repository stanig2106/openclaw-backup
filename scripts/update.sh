#!/usr/bin/env bash
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
load_env

[ -d "$PROJECT_DIR/openclaw" ] || error "Repo OpenClaw introuvable. Lance: task setup"

# Commit avant mise à jour
if gateway_is_running; then
    info "Commit des modifications système..."
    docker commit "$CONTAINER_NAME" "${IMAGE_NAME}-pre-update" || warn "Commit échoué"
    ok "Snapshot sauvegardé dans ${IMAGE_NAME}-pre-update"
fi

# Backup automatique
info "Backup avant mise à jour..."
bash "$SCRIPT_DIR/backup.sh" || warn "Backup échoué, on continue"

# Mise à jour du code source
info "Mise à jour du code source OpenClaw..."
cd "$PROJECT_DIR/openclaw"
git fetch origin
git pull --ff-only || error "Impossible de mettre à jour (conflits ?). Résous manuellement dans ./openclaw/"
cd "$PROJECT_DIR"
ok "Code source mis à jour"

# Rebuild (2 étapes)
info "Reconstruction de l'image de base..."
docker build -t openclaw:base --no-cache \
    -f "$PROJECT_DIR/openclaw/Dockerfile" \
    "$PROJECT_DIR/openclaw"
ok "Image de base reconstruite"

info "Reconstruction de l'image finale..."
docker compose build --no-cache openclaw-gateway
ok "Image finale reconstruite"

# Redémarrage
info "Redémarrage du gateway..."
docker compose down openclaw-gateway
docker compose up -d openclaw-gateway
ok "Gateway redémarré avec la nouvelle version"

echo ""
echo "  Logs:   task logs"
echo "  Statut: task status"
echo ""
