#!/usr/bin/env bash
# scripts/setup-cloudflare.sh — Interactive Cloudflare Pages setup
#
# Walks the shop owner through deploying the camera repair inventory system
# to Cloudflare Pages. Designed for non-technical users.
# See docs/cloudflare-setup.md for a visual companion guide.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_NAME="camera-repair-inventory"
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
# Step 3: GitHub repository
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

# ---------------------------------------------------------------------------
# Step 4: GitHub token
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Step 5: GitHub branch
# ---------------------------------------------------------------------------

print_step 5 "GitHub Branch"

echo "  Enter the Git branch to deploy from (usually main)."
echo ""
read -r -p "  Branch name [main]: " GITHUB_BRANCH
GITHUB_BRANCH="$(echo "${GITHUB_BRANCH:-main}" | tr -d '[:space:]')"

if [ -z "$GITHUB_BRANCH" ]; then
    GITHUB_BRANCH="main"
fi

print_ok "GitHub branch: $GITHUB_BRANCH"

# ---------------------------------------------------------------------------
# Step 6: Shop password
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Step 7: Site URL
# ---------------------------------------------------------------------------

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
# Step 8: Create Cloudflare Pages project
# ---------------------------------------------------------------------------

print_step 8 "Create Cloudflare Pages Project"

echo "  Creating Cloudflare Pages project: $PROJECT_NAME"
echo "  (If the project already exists, a warning may appear — that's normal)"
echo ""

cd "$PROJECT_ROOT"

if wrangler pages project create "$PROJECT_NAME" --production-branch "$GITHUB_BRANCH" 2>&1; then
    print_ok "Cloudflare Pages project created: $PROJECT_NAME"
else
    echo ""
    echo "  [Note] If you see an 'already exists' message, the project was created earlier."
    echo "  You can continue to the next step."
    echo "  For other errors, see ${DOCS_SETUP}."
    echo ""
    confirm_continue "  Press Enter to continue..."
fi

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
# Step 10: Set environment variables
# ---------------------------------------------------------------------------

print_step 10 "Set Environment Variables"

echo "  Please set environment variables manually in the Cloudflare Dashboard:"
echo "  Pages -> ${PROJECT_NAME} -> Settings -> Environment variables"
echo ""
echo "  Add these Production environment variables:"
echo "    GITHUB_REPO   = ${GITHUB_REPO}"
echo "    GITHUB_BRANCH = ${GITHUB_BRANCH}"
echo "    SITE_URL      = ${SITE_URL}"
echo ""
confirm_continue "  Press Enter when done..."
print_ok "Environment variables set."

# ---------------------------------------------------------------------------
# Step 11: Build and deploy
# ---------------------------------------------------------------------------

print_step 11 "Build and Deploy"

echo "  Running build.sh..."
echo ""

if bash "$SCRIPT_DIR/build.sh"; then
    print_ok "Build complete."
else
    die "build.sh failed. Check that the data directory is correct. See ${DOCS_SETUP}."
fi

echo ""
echo "  Deploying to Cloudflare Pages..."
echo ""

if wrangler pages deploy web/ --project-name "$PROJECT_NAME" --branch "$GITHUB_BRANCH"; then
    print_ok "Deploy complete."
else
    die "wrangler pages deploy failed. See ${DOCS_SETUP}."
fi

# ---------------------------------------------------------------------------
# Step 12: Open Deployed Site
# ---------------------------------------------------------------------------

print_step 12 "Open Site"

echo "  Deployment complete!"
echo ""
echo "  Your repair system is live at: $SITE_URL"
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
echo "  For help, see: ${DOCS_SETUP}"
echo ""
