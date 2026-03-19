#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="root@123.56.247.129"
REMOTE_DIR="/var/www/haerth-web"
NGINX_SITE_PATH="/etc/nginx/sites-available/haerth"
NGINX_BACKUP_DIR="/etc/nginx/site-backups"
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\n==> $*"; }

deploy() {
  log "Ensuring remote directories exist"
  ssh -o StrictHostKeyChecking=no "${REMOTE_HOST}" "\
    mkdir -p '${REMOTE_DIR}' '${NGINX_BACKUP_DIR}'\
  "

  log "Syncing static site files"
  rsync -avzc \
    -e "ssh -o StrictHostKeyChecking=no" \
    --delete \
    --exclude '.DS_Store' \
    --exclude '.git' \
    --exclude 'README.md' \
    --exclude 'deploy.sh' \
    --exclude 'nginx.haerth.conf' \
    "${PROJECT_DIR}/" \
    "${REMOTE_HOST}:${REMOTE_DIR}/"

  log "Backing up current nginx config"
  ssh -o StrictHostKeyChecking=no "${REMOTE_HOST}" "\
    if [ -f '${NGINX_SITE_PATH}' ]; then \
      cp '${NGINX_SITE_PATH}' '${NGINX_BACKUP_DIR}/haerth.'\"\$(date +%Y%m%d_%H%M%S)\"'.bak'; \
    fi\
  "

  log "Updating nginx site config"
  rsync -avzc \
    -e "ssh -o StrictHostKeyChecking=no" \
    "${PROJECT_DIR}/nginx.haerth.conf" \
    "${REMOTE_HOST}:${NGINX_SITE_PATH}"

  log "Validating nginx and reloading"
  ssh -o StrictHostKeyChecking=no "${REMOTE_HOST}" "\
    nginx -t && \
    systemctl reload nginx\
  "

  log "Deployment complete"
  log "HTTP URL: http://haerth.cn"
}

deploy
