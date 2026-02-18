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

validate_instance_name() {
    local name="$1"
    if [ ${#name} -gt 32 ]; then
        error "Le nom d'instance ne peut pas dépasser 32 caractères: '$name'"
    fi
    if ! [[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        error "Nom d'instance invalide: '$name' (minuscules, chiffres, tirets, ne commence/finit pas par un tiret)"
    fi
}

# --- Vérifications ---
info "Vérification des prérequis..."

command -v docker >/dev/null 2>&1 || error "Docker n'est pas installé. Installe-le avec: curl -fsSL https://get.docker.com | sh"
docker compose version >/dev/null 2>&1 || error "Docker Compose v2 n'est pas disponible."

ok "Docker et Docker Compose détectés"

# --- Clone OpenClaw si pas déjà fait ---
if [ ! -d "$PROJECT_DIR/openclaw" ]; then
    info "Clonage du repo OpenClaw..."
    git clone https://github.com/openclaw/openclaw.git "$PROJECT_DIR/openclaw"
    ok "OpenClaw cloné"
else
    info "Repo OpenClaw déjà présent, mise à jour..."
    cd "$PROJECT_DIR/openclaw"
    git pull --ff-only || warn "Impossible de mettre à jour, on continue avec la version actuelle"
    cd "$PROJECT_DIR"
    ok "OpenClaw à jour"
fi

# --- Nom d'instance ---
echo ""
echo -e "${BLUE}Nom de cette instance OpenClaw${NC}"
echo "  Permet de faire tourner plusieurs instances sur la meme machine."
echo "  Utilise des minuscules, chiffres et tirets (ex: main, prod, dev)"
echo ""
read -p "Nom de l'instance [main] : " INSTANCE_INPUT
INSTANCE_NAME="${INSTANCE_INPUT:-main}"
validate_instance_name "$INSTANCE_NAME"
ok "Instance: $INSTANCE_NAME"

# --- Port (demander si non-main) ---
DEFAULT_PORT=18789
if [ "$INSTANCE_NAME" != "main" ]; then
    echo ""
    echo -e "${BLUE}Port du gateway${NC}"
    echo "  Chaque instance doit utiliser un port different."
    echo ""
    read -p "Port du gateway [$((DEFAULT_PORT + 1))] : " PORT_INPUT
    GATEWAY_PORT="${PORT_INPUT:-$((DEFAULT_PORT + 1))}"

    # Vérifier si le port est déjà utilisé
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i :"$GATEWAY_PORT" >/dev/null 2>&1; then
            warn "Le port $GATEWAY_PORT semble deja utilise !"
            read -p "Continuer quand meme ? (y/N) " -n 1 -r
            echo ""
            [[ $REPLY =~ ^[Yy]$ ]] || error "Annulé. Choisis un autre port."
        fi
    fi
else
    GATEWAY_PORT=$DEFAULT_PORT
fi

export COMPOSE_PROJECT_NAME="openclaw-${INSTANCE_NAME}"

# --- Créer .env si nécessaire ---
if [ ! -f "$PROJECT_DIR/.env" ]; then
    info "Création du fichier .env depuis .env.example..."
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"

    # Générer un token gateway
    TOKEN=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^OPENCLAW_GATEWAY_TOKEN=$/OPENCLAW_GATEWAY_TOKEN=${TOKEN}/" "$PROJECT_DIR/.env"
    else
        sed -i "s/^OPENCLAW_GATEWAY_TOKEN=$/OPENCLAW_GATEWAY_TOKEN=${TOKEN}/" "$PROJECT_DIR/.env"
    fi

    ok "Fichier .env créé avec un token généré"
    warn "Édite .env pour ajouter tes clés API avant de continuer !"
    echo ""
    echo -e "  ${YELLOW}Token gateway: ${TOKEN}${NC}"
    echo ""
else
    ok "Fichier .env déjà présent"
fi

# Écrire INSTANCE_NAME et port dans le .env
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^INSTANCE_NAME=.*/INSTANCE_NAME=${INSTANCE_NAME}/" "$PROJECT_DIR/.env"
    sed -i '' "s/^OPENCLAW_GATEWAY_PORT=.*/OPENCLAW_GATEWAY_PORT=${GATEWAY_PORT}/" "$PROJECT_DIR/.env"
else
    sed -i "s/^INSTANCE_NAME=.*/INSTANCE_NAME=${INSTANCE_NAME}/" "$PROJECT_DIR/.env"
    sed -i "s/^OPENCLAW_GATEWAY_PORT=.*/OPENCLAW_GATEWAY_PORT=${GATEWAY_PORT}/" "$PROJECT_DIR/.env"
fi

# Charger le .env
set -a
source "$PROJECT_DIR/.env"
set +a

# --- Créer les répertoires de données ---
DATA_DIR="${OPENCLAW_DATA_DIR:-./data/${INSTANCE_NAME}/config}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-./data/${INSTANCE_NAME}/workspace}"

info "Création des répertoires de persistance..."
mkdir -p "$DATA_DIR" "$WORKSPACE_DIR"

# Sur Linux, s'assurer que les permissions sont correctes (uid 1000 = user node dans le conteneur)
if [[ "$OSTYPE" == "linux"* ]]; then
    if [ "$(id -u)" -eq 0 ]; then
        chown -R 1000:1000 "$DATA_DIR" "$WORKSPACE_DIR"
    else
        warn "Exécute avec sudo si tu as des erreurs de permissions: sudo chown -R 1000:1000 $DATA_DIR $WORKSPACE_DIR"
    fi
fi

ok "Répertoires créés: $DATA_DIR, $WORKSPACE_DIR"

# --- Build de l'image Docker (2 étapes) ---
info "Étape 1/2 : Construction de l'image OpenClaw de base..."
docker build -t openclaw:base \
    ${OPENCLAW_DOCKER_APT_PACKAGES:+--build-arg OPENCLAW_DOCKER_APT_PACKAGES="$OPENCLAW_DOCKER_APT_PACKAGES"} \
    -f "$PROJECT_DIR/openclaw/Dockerfile" \
    "$PROJECT_DIR/openclaw"
ok "Image de base construite"

info "Étape 2/2 : Ajout des outils (brew, go, bun, uv, ffmpeg...)..."
docker compose build gateway
ok "Image finale construite avec tous les outils"

# --- Onboarding interactif ---
info "Lancement de l'onboarding OpenClaw..."
echo -e "${YELLOW}Suis les instructions pour configurer ton fournisseur de modèle (Anthropic, OpenAI, etc.)${NC}"
echo ""
docker compose run --rm cli onboard --no-install-daemon

ok "Onboarding terminé"

# --- Démarrage ---
info "Démarrage du gateway OpenClaw..."
docker compose up -d gateway

# Attendre que le gateway soit prêt
info "Attente du démarrage du gateway..."
sleep 5

EXEC="docker compose exec gateway node dist/index.js"

# Générer l'URL du dashboard avec le bon token
DASHBOARD_URL=$($EXEC dashboard --no-open 2>&1 | grep -oE 'http://[^ ]+' | head -1 || true)

ok "Gateway démarré !"

echo ""
echo "============================================================"
echo -e "${GREEN}OpenClaw est prêt ! (instance: ${INSTANCE_NAME})${NC}"
echo "============================================================"
echo ""
if [ -n "$DASHBOARD_URL" ]; then
    echo -e "  Dashboard:  ${YELLOW}$DASHBOARD_URL${NC}"
else
    echo "  Dashboard:  http://127.0.0.1:${GATEWAY_PORT}/"
    echo "  Token:      $(grep OPENCLAW_GATEWAY_TOKEN .env | cut -d= -f2)"
fi
echo ""

# --- Pairing du dashboard ---
echo -e "${BLUE}Ouvre le lien du dashboard ci-dessus dans ton navigateur, puis reviens ici.${NC}"
echo ""
read -p "Dashboard ouvert ? Appuie sur Entrée pour approuver le device..." -r
echo ""

info "Recherche des devices en attente de pairing..."
sleep 2
DEVICES_OUTPUT=$($EXEC devices list 2>&1 || true)
REQ_ID=$(echo "$DEVICES_OUTPUT" | grep -oE '[a-f0-9-]{8,}' | head -1 || true)

if [ -n "$REQ_ID" ]; then
    info "Device trouvé ($REQ_ID), approbation..."
    $EXEC devices approve "$REQ_ID" 2>&1 || true
    ok "Device approuvé ! Refresh le dashboard."
else
    warn "Aucun device en attente. Tu peux approuver plus tard avec: task devices"
fi

echo ""
echo "  Commandes utiles:"
echo "    task logs       - Voir les logs"
echo "    task stop       - Arrêter"
echo "    task backup     - Créer un backup"
echo "    task status     - Vérifier le statut"
echo "    task devices    - Approuver un device"
echo ""
