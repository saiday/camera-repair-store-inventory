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
    echo "  步驟 ${num}：${title}"
    echo "============================================================"
}

print_error() {
    echo ""
    echo "[錯誤] $1"
    echo "  → 請參閱 ${DOCS_SETUP} 瞭解更多資訊。"
    echo ""
}

print_ok() {
    echo "  [完成] $1"
}

die() {
    print_error "$1"
    exit 1
}

confirm_continue() {
    local prompt="${1:-按 Enter 繼續...}"
    echo ""
    read -r -p "$prompt"
}

# ---------------------------------------------------------------------------
# Step 1: Check wrangler CLI
# ---------------------------------------------------------------------------

print_step 1 "檢查 Wrangler CLI"

echo "  正在檢查是否已安裝 Wrangler CLI..."

if ! command -v wrangler >/dev/null 2>&1; then
    echo ""
    echo "  尚未安裝 Wrangler CLI。"
    echo "  Wrangler 是 Cloudflare 的命令行工具，用於部署 Pages 專案。"
    echo ""
    echo "  安裝方式：npm install -g wrangler"
    echo ""
    read -r -p "  是否現在安裝？（y/n）[y]: " INSTALL_WRANGLER
    INSTALL_WRANGLER="${INSTALL_WRANGLER:-y}"

    if [ "$INSTALL_WRANGLER" = "y" ] || [ "$INSTALL_WRANGLER" = "Y" ]; then
        echo "  正在安裝 Wrangler..."
        if ! command -v npm >/dev/null 2>&1; then
            die "未找到 npm。請先安裝 Node.js（https://nodejs.org），再重新執行此指令稿。"
        fi
        npm install -g wrangler || die "安裝 Wrangler 失敗。請手動執行：npm install -g wrangler"
        print_ok "Wrangler 安裝成功。"
    else
        die "需要 Wrangler CLI 才能繼續。請安裝後重新執行。"
    fi
else
    WRANGLER_VERSION="$(wrangler --version 2>&1 | head -1)"
    print_ok "已安裝 Wrangler：$WRANGLER_VERSION"
fi

# ---------------------------------------------------------------------------
# Step 2: Cloudflare login
# ---------------------------------------------------------------------------

print_step 2 "Cloudflare 登入"

echo "  接下來將開啟瀏覽器進行 Cloudflare 登入。"
echo "  若已登入，此步驟會自動跳過。"
echo ""
confirm_continue "  按 Enter 開始登入..."

if ! wrangler login; then
    die "Cloudflare 登入失敗。請確認網路連線正常，並重新執行。"
fi

print_ok "Cloudflare 登入成功。"

# ---------------------------------------------------------------------------
# Step 3: GitHub repository
# ---------------------------------------------------------------------------

print_step 3 "GitHub 倉庫名稱"

echo "  請輸入你的 GitHub 倉庫名稱，格式為：用戶名/倉庫名稱"
echo "  範例：john/camera-repair-inventory"
echo "  （如何建立倉庫，請參閱 ${DOCS_SETUP}）"
echo ""

GITHUB_REPO=""
while true; do
    read -r -p "  GitHub 倉庫（owner/repo）: " GITHUB_REPO
    GITHUB_REPO="$(echo "$GITHUB_REPO" | tr -d '[:space:]')"

    if [ -z "$GITHUB_REPO" ]; then
        echo "  [請輸入倉庫名稱]"
        continue
    fi

    # Validate owner/repo format
    if echo "$GITHUB_REPO" | grep -qE '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'; then
        print_ok "GitHub 倉庫：$GITHUB_REPO"
        break
    else
        echo "  [格式錯誤] 請輸入正確格式，例如：john/camera-repair-inventory"
    fi
done

# ---------------------------------------------------------------------------
# Step 4: GitHub token
# ---------------------------------------------------------------------------

print_step 4 "GitHub Token"

echo "  需要一組 GitHub Fine-grained personal access token。"
echo "  此 Token 必須具備倉庫 Contents 的「Read and write」權限。"
echo "  如何建立 Token，請參閱：${DOCS_SETUP}"
echo ""
echo "  注意：輸入時不會顯示字元，請直接貼上後按 Enter。"
echo ""

GITHUB_TOKEN=""
while true; do
    read -r -s -p "  GitHub Token: " GITHUB_TOKEN
    echo ""
    GITHUB_TOKEN="$(echo "$GITHUB_TOKEN" | tr -d '[:space:]')"

    if [ -n "$GITHUB_TOKEN" ]; then
        print_ok "GitHub Token 已輸入。"
        break
    else
        echo "  [Token 不可為空，請重新輸入]"
    fi
done

# ---------------------------------------------------------------------------
# Step 5: GitHub branch
# ---------------------------------------------------------------------------

print_step 5 "GitHub 分支"

echo "  請輸入要部署的 Git 分支名稱（通常為 main）。"
echo ""
read -r -p "  分支名稱 [main]: " GITHUB_BRANCH
GITHUB_BRANCH="$(echo "${GITHUB_BRANCH:-main}" | tr -d '[:space:]')"

if [ -z "$GITHUB_BRANCH" ]; then
    GITHUB_BRANCH="main"
fi

print_ok "GitHub 分支：$GITHUB_BRANCH"

# ---------------------------------------------------------------------------
# Step 6: Shop password
# ---------------------------------------------------------------------------

print_step 6 "維修系統管理員密碼"

echo "  請設定登入維修管理系統（entry/dashboard）的密碼。"
echo "  此密碼由店主使用，請妥善保管。"
echo ""
echo "  注意：輸入時不會顯示字元，請直接輸入後按 Enter。"
echo ""

SHOP_PASSWORD=""
while true; do
    read -r -s -p "  管理員密碼: " SHOP_PASSWORD
    echo ""

    if [ -z "$SHOP_PASSWORD" ]; then
        echo "  [密碼不可為空，請重新輸入]"
        continue
    fi

    read -r -s -p "  再次確認密碼: " SHOP_PASSWORD_CONFIRM
    echo ""

    if [ "$SHOP_PASSWORD" = "$SHOP_PASSWORD_CONFIRM" ]; then
        print_ok "管理員密碼已設定。"
        break
    else
        echo "  [兩次輸入的密碼不一致，請重新輸入]"
    fi
done

# ---------------------------------------------------------------------------
# Step 7: Site URL
# ---------------------------------------------------------------------------

print_step 7 "網站 URL"

DEFAULT_SITE_URL="https://${PROJECT_NAME}.pages.dev"

echo "  請輸入部署後的網站 URL。"
echo "  若使用 Cloudflare Pages 預設網域，格式為："
echo "    https://<專案名稱>.pages.dev"
echo ""
echo "  若使用自訂網域，請輸入完整 URL（例如：https://repair.myshop.com）。"
echo ""
read -r -p "  網站 URL [$DEFAULT_SITE_URL]: " SITE_URL
SITE_URL="$(echo "${SITE_URL:-$DEFAULT_SITE_URL}" | tr -d '[:space:]')"

if [ -z "$SITE_URL" ]; then
    SITE_URL="$DEFAULT_SITE_URL"
fi

print_ok "網站 URL：$SITE_URL"

# ---------------------------------------------------------------------------
# Step 8: Create Cloudflare Pages project
# ---------------------------------------------------------------------------

print_step 8 "建立 Cloudflare Pages 專案"

echo "  正在建立 Cloudflare Pages 專案：$PROJECT_NAME"
echo "  （若專案已存在，此步驟可能會顯示警告，屬正常情況）"
echo ""

cd "$PROJECT_ROOT"

if wrangler pages project create "$PROJECT_NAME" --production-branch "$GITHUB_BRANCH" 2>&1; then
    print_ok "Cloudflare Pages 專案已建立：$PROJECT_NAME"
else
    echo ""
    echo "  [提示] 若顯示「已存在」相關訊息，表示專案先前已建立，可繼續下一步。"
    echo "  若出現其他錯誤，請參閱 ${DOCS_SETUP}。"
    echo ""
    confirm_continue "  確認後按 Enter 繼續..."
fi

# ---------------------------------------------------------------------------
# Step 9: Set secrets via wrangler
# ---------------------------------------------------------------------------

print_step 9 "設定機密環境變數"

echo "  正在設定 SHOP_PASSWORD（管理員密碼）..."
if echo "$SHOP_PASSWORD" | wrangler pages secret put SHOP_PASSWORD --project-name "$PROJECT_NAME"; then
    print_ok "SHOP_PASSWORD 已設定。"
else
    die "設定 SHOP_PASSWORD 失敗。請參閱 ${DOCS_SETUP}。"
fi

echo ""
echo "  正在設定 GITHUB_TOKEN..."
if echo "$GITHUB_TOKEN" | wrangler pages secret put GITHUB_TOKEN --project-name "$PROJECT_NAME"; then
    print_ok "GITHUB_TOKEN 已設定。"
else
    die "設定 GITHUB_TOKEN 失敗。請參閱 ${DOCS_SETUP}。"
fi

# ---------------------------------------------------------------------------
# Step 10: Set environment variables
# ---------------------------------------------------------------------------

print_step 10 "設定環境變數"

echo "  請至 Cloudflare Dashboard 手動設定環境變數："
echo "  Pages → ${PROJECT_NAME} → Settings → Environment variables"
echo ""
echo "  新增以下 Production 環境變數："
echo "    GITHUB_REPO   = ${GITHUB_REPO}"
echo "    GITHUB_BRANCH = ${GITHUB_BRANCH}"
echo "    SITE_URL      = ${SITE_URL}"
echo ""
confirm_continue "  完成後按 Enter 繼續..."
print_ok "環境變數已設定。"

# ---------------------------------------------------------------------------
# Step 11: Build and deploy
# ---------------------------------------------------------------------------

print_step 11 "建置並部署"

echo "  正在執行 build.sh..."
echo ""

if bash "$SCRIPT_DIR/build.sh"; then
    print_ok "建置完成。"
else
    die "build.sh 失敗。請確認資料目錄正確，並參閱 ${DOCS_SETUP}。"
fi

echo ""
echo "  正在部署到 Cloudflare Pages..."
echo ""

if wrangler pages deploy web/ --project-name "$PROJECT_NAME" --branch "$GITHUB_BRANCH"; then
    print_ok "部署完成。"
else
    die "wrangler pages deploy 失敗。請參閱 ${DOCS_SETUP}。"
fi

# ---------------------------------------------------------------------------
# Step 12: Open deployed URL
# ---------------------------------------------------------------------------

print_step 12 "開啟網站"

echo "  部署已完成！"
echo ""
echo "  你的維修系統已上線：$SITE_URL"
echo ""
echo "  正在開啟瀏覽器..."

if command -v open >/dev/null 2>&1; then
    # macOS
    open "$SITE_URL" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
    # Linux
    xdg-open "$SITE_URL" 2>/dev/null || true
else
    echo "  無法自動開啟瀏覽器，請手動前往：$SITE_URL"
fi

echo ""
echo "============================================================"
echo "  設定完成！"
echo "============================================================"
echo ""
echo "  維修系統 URL：$SITE_URL"
echo "  管理員可使用剛才設定的密碼登入。"
echo ""
echo "  若有問題，請參閱：${DOCS_SETUP}"
echo ""
