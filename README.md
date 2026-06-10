# 🗺️ Live Visitor Map

Real-time map showing the location of every visitor currently on the site.

## Live Demo
After deployment: `https://live-visitor-map.pages.dev`

## Architecture

```
Browser → Cloudflare Pages (index.html)
             ↓
        Cloudflare Worker (API)
             ↓
        Cloudflare KV (shared visitor store)
```

## Setup

### 1. Prerequisites
- [Cloudflare account](https://dash.cloudflare.com) (free tier works)
- [GitHub account](https://github.com)
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/) installed locally

### 2. Create KV Namespace
```bash
wrangler kv:namespace create VISITORS_KV
```
Copy the `id` from the output and paste it into `worker/wrangler.toml`.

### 3. Deploy the Worker (first time, locally)
```bash
cd worker
wrangler deploy
```
Note the Worker URL, e.g. `https://live-visitor-map-api.YOUR_SUBDOMAIN.workers.dev`

### 4. Update index.html
In `index.html`, replace the `WORKER_URL` placeholder:
```js
const WORKER_URL = 'https://live-visitor-map-api.YOUR_SUBDOMAIN.workers.dev';
```

### 5. Add GitHub Secrets
In your GitHub repo → Settings → Secrets → Actions, add:

| Secret | Where to find |
|--------|--------------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare Dashboard → My Profile → API Tokens → Create Token (use "Edit Cloudflare Workers" template + Pages) |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Dashboard → Right sidebar |

### 6. Create Cloudflare Pages Project (first time)
```bash
# from the repo root
npx wrangler pages project create live-visitor-map
```

### 7. Push to GitHub
```bash
git add .
git commit -m "initial commit"
git push origin main
```

GitHub Actions will automatically deploy on every push to `main`.

## Local Development
```bash
# serve the frontend
npx serve .

# run worker locally
cd worker && wrangler dev
```

## How it works
- Each visitor gets a unique ID stored in memory
- On page load, the browser calls `ipapi.co` to get city/country from IP
- Every 10 seconds the visitor list is synced via the Cloudflare Worker → KV
- Visitors inactive for 5+ minutes are automatically removed
