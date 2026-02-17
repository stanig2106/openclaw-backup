#!/usr/bin/env bash
# Fonctions partagées pour les opérations S3

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

check_s3_deps() {
    if ! command -v aws >/dev/null 2>&1; then
        error "AWS CLI requis. Installe-le:
  Linux:  curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o awscliv2.zip && unzip awscliv2.zip && sudo ./aws/install
  macOS:  brew install awscli"
    fi
}

check_s3_config() {
    check_s3_deps
    [ -n "${S3_BUCKET:-}" ] || error "S3_BUCKET non défini dans .env"
    [ -n "${AWS_ACCESS_KEY_ID:-}" ] || error "AWS_ACCESS_KEY_ID non défini dans .env"
    [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] || error "AWS_SECRET_ACCESS_KEY non défini dans .env"
}

# Construit la commande aws s3 avec les options endpoint/region
s3() {
    local args=()
    if [ -n "${S3_ENDPOINT:-}" ]; then
        args+=(--endpoint-url "$S3_ENDPOINT")
    fi
    if [ -n "${S3_REGION:-}" ]; then
        args+=(--region "$S3_REGION")
    fi
    aws s3 "${args[@]}" "$@"
}

s3_path() {
    echo "s3://${S3_BUCKET}/${S3_PREFIX:-openclaw-backups}/$1"
}

# Liste les backups S3, triés du plus récent au plus ancien
# Retourne: lignes "DATE SIZE FILENAME"
list_s3_backups() {
    s3 ls "$(s3_path "")" 2>/dev/null \
        | grep '\.tar\.gz$' \
        | sort -r \
        | awk '{print $1, $2, $3, $4}'
}

# Teste si un nombre est premier
is_prime() {
    local n=$1
    [ "$n" -ge 2 ] || return 1
    [ "$n" -eq 2 ] && return 0
    [ $((n % 2)) -ne 0 ] || return 1
    local i=3
    while [ $((i * i)) -le "$n" ]; do
        [ $((n % i)) -ne 0 ] || return 1
        i=$((i + 2))
    done
    return 0
}

# Génère les positions à garder (1 + nombres premiers) jusqu'à max_position, limité à max_keep
# Usage: get_keep_positions <max_position> <max_keep>
# Retourne les positions sur stdout, une par ligne
get_keep_positions() {
    local max_pos=$1
    local max_keep=$2
    local count=0

    # Position 1 = toujours gardée (la plus récente)
    echo 1
    count=1

    local i=2
    while [ "$i" -le "$max_pos" ] && [ "$count" -lt "$max_keep" ]; do
        if is_prime "$i"; then
            echo "$i"
            count=$((count + 1))
        fi
        i=$((i + 1))
    done
}
