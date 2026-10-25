# haerth

Personal site for **haerth.cn** (Aliyun ECS + nginx) and **haerth.org** (Cloudflare Workers Static Assets).

## One command (both domains)

```bash
npm install          # once — provides wrangler
./deploy.sh          # or: npm run deploy
```

That syncs `index.html` / `styles.css` / `assets/` → `public/`, then publishes the **same** `public/` tree to:

| Target | Platform | Needs |
|--------|----------|--------|
| **cn** | Aliyun ECS `root@123.56.247.129` (rsync + nginx) | SSH private key (BatchMode) |
| **org** | Cloudflare Worker `haerth` | `CLOUDFLARE_API_TOKEN` or `npx wrangler login` |

Missing credentials soft-skip that side and print what to fix; hard-fail only if a chosen target errors or nothing can run.

```bash
./deploy.sh cn    # ECS only
./deploy.sh org   # Workers only
npm run deploy:cn
npm run deploy:org
```

### Credentials

- **CN:** SSH key for `root@123.56.247.129` (e.g. `ssh-add ~/.ssh/<ecs-key>`).
- **ORG:** API token with Workers Scripts Edit (and zone DNS if recreating Custom Domains), exported as `CLOUDFLARE_API_TOKEN`, **or** interactive `npx wrangler login`.

## Files

- `index.html` / `styles.css` / `assets/` — site content (source of truth)
- `public/` — shared publish payload (`scripts/sync-public.sh`); both ECS and Workers deploy from here
- `nginx.haerth.conf` — ECS nginx for `haerth.cn` (+ local tunnel fallback for org)
- `deploy.sh` — unified deploy (cn and/or org)
- `wrangler.jsonc` — Workers Static Assets for `haerth.org` / `www.haerth.org`

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
