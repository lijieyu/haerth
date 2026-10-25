# haerth

Personal site for **haerth.cn** (Aliyun ECS + nginx) and **haerth.org** (Cloudflare Workers Static Assets).

## Files

- `index.html` / `styles.css` / `assets/` — site content (source of truth)
- `public/` — generated copy for Cloudflare Workers (`npm run sync:public`)
- `nginx.haerth.conf` — ECS nginx for `haerth.cn` (+ local tunnel fallback for org)
- `deploy.sh` — rsync site + nginx to ECS
- `wrangler.jsonc` — Workers Static Assets for `haerth.org` / `www.haerth.org`

## Deploy haerth.cn (ECS)

```bash
./deploy.sh
# or: npm run deploy:cn
```

Requires SSH to `root@123.56.247.129`.

| Item | Value |
|------|--------|
| Static files | `/var/www/haerth-web` |
| Nginx site | `/etc/nginx/sites-available/haerth` |
| Public DNS | Aliyun (`dns25/26.hichina.com`) → `123.56.247.129` |
| TLS | Let's Encrypt (`haerth.cn` / `www.haerth.cn`) |

No Cloudflare secrets are used for the CN path.

## Deploy haerth.org (Cloudflare Workers)

```bash
npm install
npm run deploy:org
```

Uses Wrangler + `CLOUDFLARE_API_TOKEN` (or `wrangler login`). Account: Jieyu's Cloudflare account; Worker name: `haerth`.

`wrangler.jsonc` attaches Custom Domains:

- `haerth.org`
- `www.haerth.org`

Wrangler creates/updates the DNS records for those Custom Domains. **Do not** keep a proxied CNAME from `haerth.org` to the Cloudflare Tunnel when using Custom Domains — delete that tunnel CNAME first (or let Wrangler fail and remove it), otherwise Custom Domain attach is rejected.

### One-time Cloudflare checklist (Jieyu)

1. Ensure zone `haerth.org` is active on Cloudflare (already done).
2. Delete DNS record: `haerth.org` CNAME → `*.cfargotunnel.com` (blocks Custom Domains).
3. Leave subdomain tunnel CNAMEs alone (`game`, `everbond`, `skills`, etc.).
4. Run `npm run deploy:org` (or merge this PR and deploy from CI/local).
5. Confirm `https://haerth.org` and `https://www.haerth.org` return the site (not 502).
6. Optional: remove the `haerth.org` ingress from the local `cloudflared` config on the ECS so the tunnel only serves subdomains.

### Why org was 502 before

Apex `haerth.org` pointed at Cloudflare Tunnel `haerth` → `http://127.0.0.1:80`, but nginx only served `haerth.cn` on the public NIC. Requests to `127.0.0.1` hit the default server (`444`), which Cloudflare surfaces as **502**.

## Dual deploy

```bash
npm run deploy   # ECS then Workers
```
