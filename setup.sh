#!/usr/bin/env bash
# ============================================================
#  setup.sh — one-shot setup for Live Visitor Map
#  Run: bash setup.sh
# ============================================================
set -e

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }
ok()     { echo -e "  ${GREEN}✔ $1${NC}"; }
warn()   { echo -e "  ${YELLOW}⚠ $1${NC}"; }
fail()   { echo -e "  ${RED}✖ $1${NC}"; exit 1; }

# ── Check tools ───────────────────────────────────────────────
header "Checking required tools"
for tool in git gh wrangler node; do
  command -v $tool &>/dev/null && ok "$tool found" || fail "$tool is not installed. Install it and re-run."
done

# ── Input ─────────────────────────────────────────────────────
header "Configuration"
read -p "  GitHub repo name [live-visitor-map]: " REPO_NAME
REPO_NAME=${REPO_NAME:-live-visitor-map}

read -p "  Make repo public? (y/n) [y]: " REPO_PUBLIC
REPO_PUBLIC=${REPO_PUBLIC:-y}
PUBLIC_FLAG=$([[ "$REPO_PUBLIC" == "y" ]] && echo "--public" || echo "--private")

# ── Auth check ────────────────────────────────────────────────
header "Checking GitHub auth"
gh auth status &>/dev/null || fail "Not logged in to GitHub. Run: gh auth login"
GH_USER=$(gh api user --jq .login)
ok "Logged in as: $GH_USER"

header "Checking Cloudflare auth"
wrangler whoami &>/dev/null || fail "Not logged in to Cloudflare. Run: wrangler login"
ok "Cloudflare auth OK"

# ── KV Namespace ──────────────────────────────────────────────
header "Creating Cloudflare KV namespace"
KV_OUTPUT=$(wrangler kv:namespace create VISITORS_KV 2>&1)
KV_ID=$(echo "$KV_OUTPUT" | grep -o '"id": "[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$KV_ID" ]; then
  warn "Could not auto-detect KV ID. Check output below:"
  echo "$KV_OUTPUT"
  read -p "  Paste your KV namespace ID: " KV_ID
fi
ok "KV namespace ID: $KV_ID"

# Update wrangler.toml
sed -i "s/REPLACE_WITH_YOUR_KV_NAMESPACE_ID/$KV_ID/" worker/wrangler.toml
ok "Updated worker/wrangler.toml"

# ── Deploy Worker ─────────────────────────────────────────────
header "Deploying Cloudflare Worker"
cd worker
WORKER_OUTPUT=$(wrangler deploy 2>&1)
WORKER_URL=$(echo "$WORKER_OUTPUT" | grep -o 'https://[^ ]*\.workers\.dev' | head -1)
cd ..
ok "Worker deployed: $WORKER_URL"

# ── Patch index.html ──────────────────────────────────────────
header "Patching index.html with Worker URL"
sed -i "s|typeof __WORKER_URL__ !== 'undefined' ? __WORKER_URL__ : ''|'$WORKER_URL'|" index.html
ok "index.html updated"

# ── GitHub repo ───────────────────────────────────────────────
header "Creating GitHub repository"
gh repo create "$REPO_NAME" $PUBLIC_FLAG --source=. --remote=origin --push 2>/dev/null || {
  # repo may already exist, just add remote and push
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/$GH_USER/$REPO_NAME.git"
  git add -A
  git commit -m "initial commit" 2>/dev/null || true
  git push -u origin main
}
ok "Repo: https://github.com/$GH_USER/$REPO_NAME"

# ── Cloudflare Pages project ──────────────────────────────────
header "Creating Cloudflare Pages project"
wrangler pages project create "$REPO_NAME" 2>/dev/null || warn "Pages project may already exist"
ok "Pages project: $REPO_NAME"

# ── GitHub secrets ────────────────────────────────────────────
header "Adding GitHub secrets"
echo ""
warn "You need to add these secrets to GitHub manually (or paste values now):"
echo ""
echo -e "  ${BOLD}CLOUDFLARE_API_TOKEN${NC} — Create at:"
echo "  https://dash.cloudflare.com/profile/api-tokens"
echo "  (Use 'Edit Cloudflare Workers' template + add Pages permissions)"
echo ""
echo -e "  ${BOLD}CLOUDFLARE_ACCOUNT_ID${NC} — Found at:"
echo "  https://dash.cloudflare.com (right sidebar)"
echo ""
read -p "  Paste CLOUDFLARE_API_TOKEN (or press Enter to skip): " CF_TOKEN
read -p "  Paste CLOUDFLARE_ACCOUNT_ID (or press Enter to skip): " CF_ACCOUNT

if [ -n "$CF_TOKEN" ]; then
  gh secret set CLOUDFLARE_API_TOKEN --body "$CF_TOKEN" --repo "$GH_USER/$REPO_NAME"
  ok "CLOUDFLARE_API_TOKEN set"
fi
if [ -n "$CF_ACCOUNT" ]; then
  gh secret set CLOUDFLARE_ACCOUNT_ID --body "$CF_ACCOUNT" --repo "$GH_USER/$REPO_NAME"
  ok "CLOUDFLARE_ACCOUNT_ID set"
fi

# ── Done ──────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✅ Done!${NC}"
echo ""
echo -e "  📦 GitHub:  https://github.com/$GH_USER/$REPO_NAME"
echo -e "  🔧 Worker:  $WORKER_URL"
echo -e "  🌍 Site:    https://$REPO_NAME.pages.dev (after first deploy)"
echo ""
echo -e "  Every ${BOLD}git push${NC} to main will auto-deploy via GitHub Actions."
echo ""
