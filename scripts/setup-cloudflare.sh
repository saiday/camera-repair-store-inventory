#!/usr/bin/env bash
# scripts/setup-cloudflare.sh — Interactive Cloudflare Pages setup
#
# Walks the shop owner through deploying the camera repair inventory system
# to Cloudflare Pages with GitHub integration (auto-deploy on push).
# Designed for non-technical users.
# See docs/cloudflare-setup.md for a visual companion guide.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_NAME="camera-repair-inventory"
WRANGLER_TOML="$PROJECT_ROOT/wrangler.toml"
DOCS_SETUP="docs/cloudflare-setup.md"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

print_step() {
    local num="$1"
    local title="$2"
    echo ""
    echo "============================================================"
    echo "  Step ${num}: ${title}"
    echo "============================================================"
}

print_error() {
    echo ""
    echo "[ERROR] $1"
    echo "  -> See ${DOCS_SETUP} for more information."
    echo ""
}

print_ok() {
    echo "  [OK] $1"
}

die() {
    print_error "$1"
    exit 1
}

confirm_continue() {
    local prompt="${1:-Press Enter to continue...}"
    echo ""
    read -r -p "$prompt"
}

# ---------------------------------------------------------------------------
# Step 1: Check wrangler CLI
# ---------------------------------------------------------------------------

print_step 1 "Check Wrangler CLI"

echo "  Checking if Wrangler CLI is installed..."

if ! command -v wrangler >/dev/null 2>&1; then
    echo ""
    echo "  Wrangler CLI is not installed."
    echo "  Wrangler is Cloudflare's CLI tool for deploying Pages projects."
    echo ""
    echo "  Install with: npm install -g wrangler"
    echo ""
    read -r -p "  Install now? (y/n) [y]: " INSTALL_WRANGLER
    INSTALL_WRANGLER="${INSTALL_WRANGLER:-y}"

    if [ "$INSTALL_WRANGLER" = "y" ] || [ "$INSTALL_WRANGLER" = "Y" ]; then
        echo "  Installing Wrangler..."
        if ! command -v npm >/dev/null 2>&1; then
            die "npm not found. Please install Node.js (https://nodejs.org) first, then re-run this script."
        fi
        npm install -g wrangler || die "Failed to install Wrangler. Please run manually: npm install -g wrangler"
        print_ok "Wrangler installed."
    else
        die "Wrangler CLI is required. Please install it and re-run this script."
    fi
else
    WRANGLER_VERSION="$(wrangler --version 2>&1 | head -1)"
    print_ok "Wrangler installed: $WRANGLER_VERSION"
fi

# ---------------------------------------------------------------------------
# Step 2: Cloudflare login
# ---------------------------------------------------------------------------

print_step 2 "Cloudflare Login"

echo "  A browser window will open for Cloudflare authentication."
echo "  If you're already logged in, this step will be skipped."
echo ""
confirm_continue "  Press Enter to start login..."

if ! wrangler login; then
    die "Cloudflare login failed. Check your network connection and try again."
fi

print_ok "Cloudflare login successful."

# ---------------------------------------------------------------------------
# Step 3: Collect info — GitHub repo, token, branch, password, site URL
# ---------------------------------------------------------------------------

print_step 3 "GitHub Repository"

echo "  Enter your GitHub repository name in the format: owner/repo"
echo "  Example: john/camera-repair-inventory"
echo "  (See ${DOCS_SETUP} for how to create a repository)"
echo ""

GITHUB_REPO=""
while true; do
    read -r -p "  GitHub repo (owner/repo): " GITHUB_REPO
    GITHUB_REPO="$(echo "$GITHUB_REPO" | tr -d '[:space:]')"

    if [ -z "$GITHUB_REPO" ]; then
        echo "  [Please enter a repository name]"
        continue
    fi

    # Validate owner/repo format
    if echo "$GITHUB_REPO" | grep -qE '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'; then
        print_ok "GitHub repo: $GITHUB_REPO"
        break
    else
        echo "  [Invalid format] Please use: owner/repo (e.g. john/camera-repair-inventory)"
    fi
done

print_step 4 "GitHub Token"

echo "  A GitHub fine-grained personal access token is required."
echo "  The token must have Contents \"Read and write\" permission for the repo."
echo "  See ${DOCS_SETUP} for how to create a token."
echo ""
echo "  Note: Input will be hidden. Paste your token and press Enter."
echo ""

GITHUB_TOKEN=""
while true; do
    read -r -s -p "  GitHub Token: " GITHUB_TOKEN
    echo ""
    GITHUB_TOKEN="$(echo "$GITHUB_TOKEN" | tr -d '[:space:]')"

    if [ -n "$GITHUB_TOKEN" ]; then
        print_ok "GitHub Token entered."
        break
    else
        echo "  [Token cannot be empty, please try again]"
    fi
done

print_step 5 "GitHub Branch"

echo "  Enter the Git branch to deploy from (usually main)."
echo ""
read -r -p "  Branch name [main]: " GITHUB_BRANCH
GITHUB_BRANCH="$(echo "${GITHUB_BRANCH:-main}" | tr -d '[:space:]')"

if [ -z "$GITHUB_BRANCH" ]; then
    GITHUB_BRANCH="main"
fi

print_ok "GitHub branch: $GITHUB_BRANCH"

print_step 6 "Shop Admin Password"

echo "  Set a password for accessing the repair management system (entry/dashboard)."
echo "  This password is for the shop owner. Keep it safe."
echo ""
echo "  Note: Input will be hidden."
echo ""

SHOP_PASSWORD=""
while true; do
    read -r -s -p "  Admin password: " SHOP_PASSWORD
    echo ""

    if [ -z "$SHOP_PASSWORD" ]; then
        echo "  [Password cannot be empty, please try again]"
        continue
    fi

    read -r -s -p "  Confirm password: " SHOP_PASSWORD_CONFIRM
    echo ""

    if [ "$SHOP_PASSWORD" = "$SHOP_PASSWORD_CONFIRM" ]; then
        print_ok "Admin password set."
        break
    else
        echo "  [Passwords do not match, please try again]"
    fi
done

print_step 7 "Site URL"

DEFAULT_SITE_URL="https://${PROJECT_NAME}.pages.dev"

echo "  Enter the deployed site URL."
echo "  For the default Cloudflare Pages domain, the format is:"
echo "    https://<project-name>.pages.dev"
echo ""
echo "  For a custom domain, enter the full URL (e.g. https://repair.myshop.com)."
echo ""
read -r -p "  Site URL [$DEFAULT_SITE_URL]: " SITE_URL
SITE_URL="$(echo "${SITE_URL:-$DEFAULT_SITE_URL}" | tr -d '[:space:]')"

if [ -z "$SITE_URL" ]; then
    SITE_URL="$DEFAULT_SITE_URL"
fi

print_ok "Site URL: $SITE_URL"

# ---------------------------------------------------------------------------
# Step 8: Create Cloudflare Pages project via Dashboard (GitHub connected)
# ---------------------------------------------------------------------------

print_step 8 "Create Cloudflare Pages Project (GitHub Connected)"

echo "  To enable auto-deploy on push, the project must be created in the"
echo "  Cloudflare Dashboard with GitHub connected."
echo ""
echo "  A browser will open to the Cloudflare Pages setup page."
echo "  Follow these steps:"
echo ""
echo "    1. Click \"Create a project\" -> \"Connect to Git\""
echo "    2. Select your GitHub account and repository: $GITHUB_REPO"
echo "    3. Set these build settings:"
echo "       - Project name:      $PROJECT_NAME"
echo "       - Production branch: $GITHUB_BRANCH"
echo "       - Build command:     bash scripts/build.sh"
echo "       - Build output dir:  web"
echo "    4. Click \"Save and Deploy\""
echo ""
echo "  The first deploy may fail (secrets are not set yet) — that's normal."
echo ""

CLOUDFLARE_PAGES_URL="https://dash.cloudflare.com/?to=/:account/pages/new/provider/github"

confirm_continue "  Press Enter to open the Cloudflare Dashboard..."

if command -v open >/dev/null 2>&1; then
    open "$CLOUDFLARE_PAGES_URL" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$CLOUDFLARE_PAGES_URL" 2>/dev/null || true
else
    echo "  Could not open browser. Please visit:"
    echo "  $CLOUDFLARE_PAGES_URL"
fi

confirm_continue "  Press Enter when the project is created..."

print_ok "Cloudflare Pages project created."

# ---------------------------------------------------------------------------
# Step 9: Set secrets via wrangler
# ---------------------------------------------------------------------------

print_step 9 "Set Secret Environment Variables"

echo "  Setting SHOP_PASSWORD (admin password)..."
if echo "$SHOP_PASSWORD" | wrangler pages secret put SHOP_PASSWORD --project-name "$PROJECT_NAME"; then
    print_ok "SHOP_PASSWORD set."
else
    die "Failed to set SHOP_PASSWORD. See ${DOCS_SETUP}."
fi

echo ""
echo "  Setting GITHUB_TOKEN..."
if echo "$GITHUB_TOKEN" | wrangler pages secret put GITHUB_TOKEN --project-name "$PROJECT_NAME"; then
    print_ok "GITHUB_TOKEN set."
else
    die "Failed to set GITHUB_TOKEN. See ${DOCS_SETUP}."
fi

# ---------------------------------------------------------------------------
# Step 10: Write environment variables to wrangler.toml
# ---------------------------------------------------------------------------

print_step 10 "Write Environment Variables"

echo "  Writing GITHUB_REPO, GITHUB_BRANCH, and SITE_URL to wrangler.toml..."

# Rewrite wrangler.toml with vars section
cat > "$WRANGLER_TOML" <<TOML
name = "$PROJECT_NAME"
pages_build_output_dir = "web"
compatibility_date = "2026-03-22"

[vars]
GITHUB_REPO = "$GITHUB_REPO"
GITHUB_BRANCH = "$GITHUB_BRANCH"
SITE_URL = "$SITE_URL"
TOML

print_ok "wrangler.toml updated."

# ---------------------------------------------------------------------------
# Step 11: Commit and push to trigger deploy
# ---------------------------------------------------------------------------

print_step 11 "Commit and Deploy"

echo "  Committing wrangler.toml and pushing to trigger a deploy..."
echo ""

cd "$PROJECT_ROOT"

git add wrangler.toml
if git diff --cached --quiet; then
    echo "  No changes to commit (wrangler.toml already up to date)."
    echo "  Pushing to trigger deploy..."
    git push origin "$GITHUB_BRANCH" || die "git push failed. Check your remote settings."
else
    git commit -m "chore: add Cloudflare environment variables to wrangler.toml"
    git push origin "$GITHUB_BRANCH" || die "git push failed. Check your remote settings."
fi

print_ok "Pushed to $GITHUB_BRANCH — Cloudflare will auto-deploy."

# ---------------------------------------------------------------------------
# Step 12: Open Deployed Site
# ---------------------------------------------------------------------------

print_step 12 "Open Site"

echo "  Deployment triggered! It may take a minute to finish building."
echo ""
echo "  Your repair system will be live at: $SITE_URL"
echo ""
echo "  Opening browser in 3 seconds..."
sleep 3

if command -v open >/dev/null 2>&1; then
    # macOS
    open "$SITE_URL" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
    # Linux
    xdg-open "$SITE_URL" 2>/dev/null || true
else
    echo "  Could not open browser automatically. Please visit: $SITE_URL"
fi

echo ""
echo "============================================================"
echo "  Setup complete!"
echo "============================================================"
echo ""
echo "  Repair system URL: $SITE_URL"
echo "  Log in with the admin password you set."
echo ""
echo "  Auto-deploy is enabled: push to '$GITHUB_BRANCH' to update the site."
echo ""
echo "  For help, see: ${DOCS_SETUP}"
echo ""
