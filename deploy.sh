#!/usr/bin/env bash
# Publish the same static site to haerth.cn (Aliyun ECS) and/or haerth.org
# (Cloudflare Workers). Default: both.
#
# Usage:
#   ./deploy.sh           # cn + org (skips a target only when credentials are missing)
#   ./deploy.sh all
#   ./deploy.sh cn
#   ./deploy.sh org
#   npm run deploy        # same as ./deploy.sh
#
# Credentials:
#   CN  — SSH key that can log in as root@123.56.247.129 (BatchMode)
#   ORG — CLOUDFLARE_API_TOKEN (Workers Scripts Edit) or `wrangler login`
set -euo pipefail

REMOTE_HOST="root@123.56.247.129"
REMOTE_DIR="/var/www/haerth-web"
NGINX_SITE_PATH="/etc/nginx/sites-available/haerth"
NGINX_BACKUP_DIR="/etc/nginx/site-backups"
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PUBLIC_DIR="${PROJECT_DIR}/public"
TARGET="${1:-all}"

log() { echo -e "\n==> $*"; }
warn() { echo -e "\n!!  $*" >&2; }

sync_public() {
  bash "${PROJECT_DIR}/scripts/sync-public.sh"
}

can_ssh_cn() {
  ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no \
    "${REMOTE_HOST}" "true" >/dev/null 2>&1
}

wrangler_bin() {
  if [[ -x "${PROJECT_DIR}/node_modules/.bin/wrangler" ]]; then
    echo "${PROJECT_DIR}/node_modules/.bin/wrangler"
    return 0
  fi
  if command -v npx >/dev/null 2>&1; then
    echo "npx --yes wrangler"
    return 0
  fi
  return 1
}

can_wrangler_org() {
  # Prefer an explicit token (required for non-interactive CI / cloud agents).
  if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    return 0
  fi
  local bin out
  bin="$(wrangler_bin)" || return 1
  # `wrangler whoami` often exits 0 even when logged out — check the text.
  out="$(cd "${PROJECT_DIR}" && ${bin} whoami 2>&1)" || true
  if grep -qiE 'not authenticated|not logged in|please run .*login|unable to authenticate' <<<"${out}"; then
    return 1
  fi
  if grep -qiE 'e-?mail|account name|user id|@' <<<"${out}"; then
    return 0
  fi
  return 1
}

deploy_cn() {
  log "Deploying haerth.cn (ECS ${REMOTE_HOST})"

  if ! can_ssh_cn; then
    warn "Skipping haerth.cn: SSH to ${REMOTE_HOST} failed (BatchMode)."
    warn "Add your ECS SSH private key locally, then re-run: ./deploy.sh cn"
    warn "  (or: ssh-add /path/to/key && ./deploy.sh)"
    return 2
  fi

  sync_public

  log "Ensuring remote directories exist"
  ssh -o StrictHostKeyChecking=no "${REMOTE_HOST}" "\
    mkdir -p '${REMOTE_DIR}' '${NGINX_BACKUP_DIR}'\
  "

  log "Syncing static site files from public/ -> ${REMOTE_DIR}"
  rsync -avzc \
    -e "ssh -o StrictHostKeyChecking=no" \
    --delete \
    --exclude '.DS_Store' \
    "${PUBLIC_DIR}/" \
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

  log "haerth.cn done → https://haerth.cn"
  return 0
}

deploy_org() {
  log "Deploying haerth.org (Cloudflare Workers)"

  if ! can_wrangler_org; then
    warn "Skipping haerth.org: no Cloudflare credentials."
    warn "Set CLOUDFLARE_API_TOKEN or run: npx wrangler login"
    warn "Then re-run: ./deploy.sh org"
    return 2
  fi

  sync_public

  local bin
  bin="$(wrangler_bin)" || {
    warn "wrangler not found. Run: npm install"
    return 1
  }

  if ! (cd "${PROJECT_DIR}" && ${bin} deploy); then
    warn "wrangler deploy failed for haerth.org"
    return 1
  fi

  log "haerth.org done → https://haerth.org (and https://www.haerth.org)"
  return 0
}

status_line() {
  local label="$1" rc="$2"
  case "${rc}" in
    0) echo "  ${label}: ok" ;;
    2) echo "  ${label}: skipped (missing credentials)" ;;
    *) echo "  ${label}: failed (${rc})" ;;
  esac
}

main() {
  case "${TARGET}" in
    all|cn|org) ;;
    *)
      echo "Usage: $0 [all|cn|org]" >&2
      exit 1
      ;;
  esac

  local cn_rc=0 org_rc=0

  if [[ "${TARGET}" == "all" || "${TARGET}" == "cn" ]]; then
    set +e
    deploy_cn
    cn_rc=$?
    set -e
  fi
  if [[ "${TARGET}" == "all" || "${TARGET}" == "org" ]]; then
    set +e
    deploy_org
    org_rc=$?
    set -e
  fi

  log "Summary"
  if [[ "${TARGET}" == "all" || "${TARGET}" == "cn" ]]; then
    status_line "cn " "${cn_rc}"
  fi
  if [[ "${TARGET}" == "all" || "${TARGET}" == "org" ]]; then
    status_line "org" "${org_rc}"
  fi

  if [[ "${TARGET}" == "cn" ]]; then
    [[ "${cn_rc}" -eq 0 ]] || exit "${cn_rc}"
    exit 0
  fi
  if [[ "${TARGET}" == "org" ]]; then
    [[ "${org_rc}" -eq 0 ]] || exit "${org_rc}"
    exit 0
  fi

  # all
  if [[ "${cn_rc}" -eq 1 || "${org_rc}" -eq 1 ]]; then
    exit 1
  fi
  if [[ "${cn_rc}" -eq 2 && "${org_rc}" -eq 2 ]]; then
    warn "Nothing deployed — need SSH for cn and/or CLOUDFLARE_API_TOKEN for org."
    exit 1
  fi
  if [[ "${cn_rc}" -eq 2 || "${org_rc}" -eq 2 ]]; then
    warn "Partial deploy. Install missing credentials and re-run ./deploy.sh"
    exit 0
  fi
  exit 0
}

main
