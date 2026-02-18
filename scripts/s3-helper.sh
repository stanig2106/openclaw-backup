#!/usr/bin/env bash
# Fonctions S3 pour les scripts OpenClaw

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

s3() {
    local args=()
    [ -n "${S3_ENDPOINT:-}" ] && args+=(--endpoint-url "$S3_ENDPOINT")
    [ -n "${S3_REGION:-}" ] && args+=(--region "$S3_REGION")
    aws s3 "${args[@]}" "$@"
}

s3_path() {
    echo "s3://${S3_BUCKET}/${S3_PREFIX:-openclaw-backups}/${INSTANCE_NAME:-main}/$1"
}

list_s3_backups() {
    s3 ls "$(s3_path "")" 2>/dev/null \
        | grep '\.tar\.gz$' \
        | sort -r \
        | awk '{print $1, $2, $3, $4}'
}
