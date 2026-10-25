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
# Credentials (local or CI):
#   CN  — SSH BatchMode access. Either:
#           • default agent key / ~/.ssh that can reach the host, or
#           • HAERTH_SSH_PRIVATE_KEY (+ optional HAERTH_SSH_HOST / HAERTH_SSH_USER)
#   ORG — CLOUDFLARE_API_TOKEN (Workers Edit; optional CLOUDFLARE_ACCOUNT_ID)
#         or interactive `wrangler login` locally
set -euo pipefail

HAERTH_SSH_HOST="${HAERTH_SSH_HOST:-123.56.247.129}"
HAERTH_SSH_USER="${HAERTH_SSH_USER:-root}"
REMOTE_HOST="${HAERTH_SSH_USER}@${HAERTH_SSH_HOST}"
REMOTE_DIR="/var/www/haerth-web"
NGINX_SITE_PATH="/etc/nginx/sites-available/haerth"
NGINX_BACKUP_DIR="/etc/nginx/site-backups"
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PUBLIC_DIR="${PROJECT_DIR}/public"
TARGET="${1:-all}"

SSH_IDENTITY_FILE=""
SSH_BASE_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=15
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

log() { echo -e "\n==> $*"; }
warn() { echo -e "\n!!  $*" >&2; }

cleanup() {
  if [[ -n "${SSH_IDENTITY_FILE}" && -f "${SSH_IDENTITY_FILE}" ]]; then
    rm -f "${SSH_IDENTITY_FILE}"
  fi
}
trap cleanup EXIT

# Load HAERTH_SSH_PRIVATE_KEY into a temp identity file for CI / non-interactive use.
setup_ssh_identity() {
  if [[ -z "${HAERTH_SSH_PRIVATE_KEY:-}" ]]; then
    return 0
  fi
  SSH_IDENTITY_FILE="$(mktemp)"
  # GitHub Secrets may be multiline PEM, or a single line with literal \n.
  if [[ "$(printf '%s' "${HAERTH_SSH_PRIVATE_KEY}" | head -n 1)" == *"BEGIN"* ]]; then
    printf '%s\n' "${HAERTH_SSH_PRIVATE_KEY}" >"${SSH_IDENTITY_FILE}"
  else
    printf '%s\n' "${HAERTH_SSH_PRIVATE_KEY}" | sed 's/\\n/\n/g' >"${SSH_IDENTITY_FILE}"
  fi
  chmod 600 "${SSH_IDENTITY_FILE}"
  SSH_BASE_OPTS+=(-i "${SSH_IDENTITY_FILE}" -o IdentitiesOnly=yes)
}

ssh_cmd() {
  ssh "${SSH_BASE_OPTS[@]}" "${REMOTE_HOST}" "$@"
}

rsync_ssh() {
  # Build ssh command string for rsync -e
  local e="ssh"
  local opt
  for opt in "${SSH_BASE_OPTS[@]}"; do
    e+=" $(printf '%q' "${opt}")"
  done
  rsync -avzc -e "${e}" "$@"
}

sync_public() {
  bash "${PROJECT_DIR}/scripts/sync-public.sh"
}

can_ssh_cn() {
  # Prefer explicit key when provided; otherwise try agent/default keys.
  if [[ -z "${HAERTH_SSH_PRIVATE_KEY:-}" && -z "${SSH_AUTH_SOCK:-}" && ! -f "${HOME}/.ssh/id_rsa" && ! -f "${HOME}/.ssh/id_ed25519" ]]; then
    # No obvious SSH material — skip early in CI without the secret.
    if [[ -n "${CI:-}${GITHUB_ACTIONS:-}" ]]; then
      return 1
    fi
  fi
  ssh_cmd "true" >/dev/null 2>&1
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
  if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    return 0
  fi
  local bin out
  bin="$(wrangler_bin)" || return 1
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
    warn "Provide HAERTH_SSH_PRIVATE_KEY (and optional HAERTH_SSH_HOST / HAERTH_SSH_USER),"
    warn "  or use a local ssh-agent key that can reach the host."
    return 2
  fi

  sync_public

  log "Ensuring remote directories exist"
  ssh_cmd "mkdir -p '${REMOTE_DIR}' '${NGINX_BACKUP_DIR}'"

  log "Syncing static site files from public/ -> ${REMOTE_DIR}"
  rsync_ssh \
    --delete \
    --exclude '.DS_Store' \
    "${PUBLIC_DIR}/" \
    "${REMOTE_HOST}:${REMOTE_DIR}/"

  log "Backing up current nginx config"
  ssh_cmd "\
    if [ -f '${NGINX_SITE_PATH}' ]; then \
      cp '${NGINX_SITE_PATH}' '${NGINX_BACKUP_DIR}/haerth.'\"\$(date +%Y%m%d_%H%M%S)\"'.bak'; \
    fi\
  "

  log "Updating nginx site config"
  rsync_ssh \
    "${PROJECT_DIR}/nginx.haerth.conf" \
    "${REMOTE_HOST}:${NGINX_SITE_PATH}"

  log "Validating nginx and reloading"
  ssh_cmd "nginx -t && systemctl reload nginx"

  log "haerth.cn done → https://haerth.cn"
  return 0
}

deploy_org() {
  log "Deploying haerth.org (Cloudflare Workers)"

  if ! can_wrangler_org; then
    warn "Skipping haerth.org: no Cloudflare credentials."
    warn "Set CLOUDFLARE_API_TOKEN (optional CLOUDFLARE_ACCOUNT_ID) or run: npx wrangler login"
    return 2
  fi

  sync_public

  local bin
  bin="$(wrangler_bin)" || {
    warn "wrangler not found. Run: npm install / npm ci"
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

  setup_ssh_identity

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
    warn "Nothing deployed — need HAERTH_SSH_PRIVATE_KEY for cn and/or CLOUDFLARE_API_TOKEN for org."
    exit 1
  fi
  if [[ "${cn_rc}" -eq 2 || "${org_rc}" -eq 2 ]]; then
    warn "Partial deploy (one target skipped). Add the missing GitHub secret / local credential for full dual publish."
    exit 0
  fi
  exit 0
}

main
