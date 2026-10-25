# haerth

Personal site for **haerth.cn** (Aliyun ECS + nginx) and **haerth.org** (Cloudflare Workers Static Assets).

## Deploy (recommended: GitHub Actions)

Push or merge to **`main`** runs [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml). You can also run it manually (**Actions → Deploy → Run workflow**) with target `all` / `cn` / `org`.

`./deploy.sh` publishes the same `public/` tree to both sides. A target is **soft-skipped** when its secrets are missing (job still succeeds if the other side deploys). Hard-fail only if a chosen target errors or nothing can run.

### One-time GitHub secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret**.

| Secret name | Required for | What to paste |
|-------------|--------------|---------------|
| `HAERTH_SSH_PRIVATE_KEY` | **cn** | Full PEM private key that can SSH as the ECS deploy user (include `-----BEGIN…` / `-----END…` lines) |
| `HAERTH_SSH_HOST` | cn (optional) | ECS host, default `123.56.247.129` if unset |
| `HAERTH_SSH_USER` | cn (optional) | SSH user, default `root` if unset |
| `CLOUDFLARE_API_TOKEN` | **org** | [API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/) with **Workers Scripts Edit** (add zone DNS edit if you recreate Custom Domains) |
| `CLOUDFLARE_ACCOUNT_ID` | org (optional) | Cloudflare account id (helps non-interactive Wrangler) |

Do **not** commit real keys. After secrets are set, the next push to `main` (or a manual workflow run) deploys automatically — no laptop `./deploy.sh` required.

### Local / manual (optional)

```bash
npm install
./deploy.sh          # or: npm run deploy
./deploy.sh cn       # ECS only
./deploy.sh org      # Workers only
```

| Target | Platform | Needs |
|--------|----------|--------|
| **cn** | Aliyun ECS (rsync + nginx) | `HAERTH_SSH_PRIVATE_KEY` or a local ssh-agent key |
| **org** | Cloudflare Worker `haerth` | `CLOUDFLARE_API_TOKEN` or `npx wrangler login` |

## Files

- `index.html` / `styles.css` / `assets/` — site content (source of truth)
- `public/` — shared publish payload (`scripts/sync-public.sh`); both ECS and Workers deploy from here
- `nginx.haerth.conf` — ECS nginx for `haerth.cn` (+ local tunnel fallback for org)
- `deploy.sh` — unified deploy (cn and/or org); CI-friendly via env secrets
- `wrangler.jsonc` — Workers Static Assets for `haerth.org` / `www.haerth.org`
- `.github/workflows/deploy.yml` — auto-deploy on `main`

## Platform details

### haerth.cn (ECS)

| Item | Value |
|------|--------|
| Static files | `/var/www/haerth-web` (contents of `public/`) |
| Nginx site | `/etc/nginx/sites-available/haerth` |
| Public DNS | Aliyun (`dns25/26.hichina.com`) → `123.56.247.129` |
| TLS | Let's Encrypt (`haerth.cn` / `www.haerth.cn`) |

### haerth.org (Workers)

Worker name: `haerth`. Custom Domains (in `wrangler.jsonc`):

- `haerth.org`
- `www.haerth.org`

Do **not** keep a proxied CNAME from `haerth.org` to the Cloudflare Tunnel when using Custom Domains — that record blocks attach.

### Why org was 502 before

The Tunnel was up. Apex `haerth.org` CNAME → tunnel → `http://127.0.0.1:80`, but nginx only served `haerth.cn` on the public NIC. Localhost hit the default server (`return 444`), which Cloudflare surfaces as **502**.
