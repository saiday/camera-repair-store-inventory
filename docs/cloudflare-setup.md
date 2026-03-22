# Cloudflare 設定指南

此指南說明如何將維修系統部署到 Cloudflare Pages。完成此步驟後，維修系統將在網際網路上線，客戶可以透過密碼查看維修進度。

---

## 前置需求

請先確認已安裝以下工具：

### 1. Node.js

檢查是否已安裝：

```bash
node --version
npm --version
```

若未安裝，請造訪 https://nodejs.org 下載安裝（建議 LTS 版本）。

### 2. Wrangler CLI

Wrangler 是 Cloudflare 的命令行工具，用於管理 Pages 專案。安裝方式：

```bash
npm install -g wrangler
```

確認安裝成功：

```bash
wrangler --version
```

---

## GitHub 倉庫設定

系統透過 GitHub API 進行建檔和編輯，因此需要 GitHub 帳號和倉庫。

### 1. 建立 GitHub 帳號

若無 GitHub 帳號，請造訪 https://github.com/signup 註冊。

### 2. 建立新的私人倉庫

1. 登入 GitHub
2. 點選頁面右上角的 `+` 圖示，選擇 `New repository`
3. 輸入倉庫名稱（例如：`camera-repair-inventory`）
4. 選擇 `Private`（私人倉庫）
5. 點選 `Create repository`

記住你的倉庫完整名稱，格式為：`你的用戶名/倉庫名稱`（例如：`john/camera-repair-inventory`）

### 3. 上傳本機代碼到 GitHub

若尚未將本機代碼推送到 GitHub，執行以下步驟：

```bash
cd /Users/saiday/projects/camera-repair-store-inventory

# 初始化 Git（若尚未初始化）
git remote add origin https://github.com/你的用戶名/camera-repair-inventory.git
git branch -M main
git push -u origin main
```

確認所有檔案已推送到 GitHub。

---

## 建立 GitHub Token

Cloudflare Workers 需要 GitHub token 來建檔和編輯維修單。

### 步驟 1：進入 GitHub Settings

1. 登入 GitHub
2. 點選右上角頭像，選擇 `Settings`
3. 向下捲動左側選單，找到 `Developer settings`（最下方）
4. 點選 `Personal access tokens` 下的 `Fine-grained tokens`

### 步驟 2：建立新 Token

1. 點選 `Generate new token`
2. 輸入 Token 名稱（例如：`camera-repair-inventory-cloudflare`）
3. **設定過期日期**（建議 90 天或更長）
4. **在 Repository access 部分**選擇 `Only select repositories`
5. 從下拉選單選擇你建立的倉庫（`camera-repair-inventory`）

### 步驟 3：設定權限

展開 `Repository permissions` 部分，設定以下權限：

| 權限 | 選項 |
|---|---|
| Contents | `Read and write` |
| 其他 | `No access` |

### 步驟 4：複製 Token

1. 點選 `Generate token`
2. **立即複製顯示的 Token**（這是唯一一次可以看到完整 Token）
3. 將 Token 保存在安全的地方（例如密碼管理器）

---

## 執行設定指令稿

執行 `setup-cloudflare.sh` 指令稿來配置系統。此指令稿會詢問必要資訊並連線 Cloudflare。

### 執行方式

```bash
cd /Users/saiday/projects/camera-repair-store-inventory

./scripts/setup-cloudflare.sh
```

### 設定過程

指令稿會提示輸入：

1. **Cloudflare 帳號電子郵件** — 你登入 Cloudflare 的電子郵件
2. **Cloudflare API Token** — 從 Cloudflare dashboard 生成（見下方說明）
3. **GitHub Token** — 之前建立的 Fine-grained personal access token
4. **GitHub 倉庫** — 格式為 `用戶名/倉庫名稱`（例如：`john/camera-repair-inventory`）
5. **維修系統密碼** — 用於登入維修系統的密碼（例如：`myshoppass123`）

**每次輸入後按 Enter 確認。**

### 獲取 Cloudflare API Token

若尚未有 API Token：

1. 登入 Cloudflare (https://dash.cloudflare.com)
2. 點選右上角帳號頭像，選擇 `My Profile`
3. 左側選單點選 `API Tokens`
4. 點選 `Create Token`
5. 選擇 `Edit Cloudflare Workers` 樣板
6. 在 `Account Resources` 設定 `Include: All accounts`
7. 點選 `Continue to summary` → `Create Token`
8. 複製顯示的 Token

---

## 驗證部署

設定完成後，驗證系統已成功部署：

### 1. 檢查 Cloudflare Pages

1. 登入 Cloudflare Dashboard
2. 點選左側 `Workers & Pages`
3. 選擇 `Pages` 標籤
4. 應該看到你的專案（`camera-repair-inventory`）
5. 點選專案查看部署狀態

### 2. 訪問維修系統

1. 點選 `Visit site` 或在瀏覽器中輸入分配的 URL（格式：`https://camera-repair-inventory.pages.dev`）
2. 系統會要求輸入密碼（你在設定時輸入的密碼）
3. 輸入密碼後應該進入維修儀表板

### 3. 測試建檔功能

1. 在儀表板點選 `新增維修單`
2. 填入測試資料並提交
3. 系統應該建檔新項目並立即顯示在列表中

### 4. 測試客戶頁面

1. 進入新建的維修單進行編輯
2. 確保已設定 `頁面密碼`
3. 在新瀏覽器分頁中訪問客戶連結（格式：`https://camera-repair-inventory.pages.dev/item/CAM-xxxxxxxx-xxxxx-001`）
4. 系統應要求輸入頁面密碼
5. 輸入密碼後應顯示客戶維修進度頁面

---

## 常見問題排查

### 部署失敗

**症狀：** Cloudflare dashboard 顯示部署失敗

**解決方案：**

1. 檢查 Cloudflare Pages 的建置日誌：
   - Dashboard → Pages → 選擇專案 → 點選最新部署 → 查看 Logs
2. 檢查常見錯誤：
   - Node.js 版本不相容：升級 Node.js 至 18.0.0 以上
   - 環境變數遺失：確認在 Cloudflare dashboard 設定所有必要的環境變數

### 無法建檔新維修單

**症狀：** 提交表單後顯示錯誤

**解決方案：**

1. 檢查 GitHub Token 是否有效：
   - 確認 Token 未過期
   - 確認 Token 有 `Contents: Read and write` 權限
2. 檢查 GitHub 倉庫權限：
   - 確認 Token 有該倉庫的存取權限
3. 檢查瀏覽器控制台錯誤：
   - 開啟瀏覽器開發者工具（F12）→ Console 標籤
   - 查看是否有錯誤訊息

### 客戶無法訪問項目頁面

**症狀：** 輸入密碼後仍顯示「密碼錯誤」

**解決方案：**

1. 確認頁面密碼已保存：
   - 編輯維修單，確認 `頁面密碼` 欄位有值
2. 清除瀏覽器快取：
   - 開啟無痕模式嘗試
3. 檢查部署是否完成：
   - 在 Cloudflare dashboard 確認最新部署狀態為 "Active"

### 儀表板載入緩慢

**症狀：** 維修列表或儀表板載入需時長時間

**解決方案：**

1. 清除瀏覽器快取
2. 檢查網際網路連線速度
3. 嘗試在不同裝置或瀏覽器測試
4. 若持續緩慢，聯繫 Cloudflare 支援

---

## 後續維護

### 定期備份

定期將本機倉庫推送到 GitHub：

```bash
git add .
git commit -m "Regular backup"
git push origin main
```

### 更新密碼

如需更改維修系統或頁面密碼：

1. 聯繫技術人員，他們可以透過：
   ```bash
   wrangler secret put SHOP_PASSWORD --env production
   ```
   更新環境變數

### 監控部署

定期檢查 Cloudflare Pages 部署日誌，確保系統穩定運作。

---

## 需要協助？

如遇到問題：

1. **檢查本指南常見問題排查部分**
2. **查閱 Cloudflare 官方文件：** https://developers.cloudflare.com/pages/
3. **檢查 GitHub 文件：** https://docs.github.com/
4. **聯繫技術支援**
