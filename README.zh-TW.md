# CatDesk Custom

[English](README.md) | [繁體中文](README.zh-TW.md)

這是漢秦哥目前 Mac 上 CatDesk production 使用的 private downstream repository。

設計原則刻意保持很窄：

> **官方 Xeift/CatDesk upstream + 最小必要的外部檔案路徑 patch + 可選的薄層 OpenAI MCP Apps 相容能力**

Cloudflare、launchd、code signing、正式啟用流程都屬於部署層，不算 CatDesk source custom。

## 目前正式狀態

- **官方 upstream：** https://github.com/Xeift/CatDesk
- **Private downstream：** https://github.com/HCH725/CatDesk-custom
- **目前接受的 upstream release：** `v0.9.5`
- **目前 upstream commit：** `f4f4bcc6a14b87f00d17f102f3006dfd96c0b341`
- **目前 downstream release：** `v0.9.5-custom.2`
- **Production runtime：** `/Users/hong/.local/share/catdesk/runtime/bin/catdesk`
- **目前 production SHA256：** `8c98eb715a9366ce5c3cc3725de609dbd27575916bca33ec05c7f861586612fe`
- **固定簽署 Identifier：** `com.hong.catdesk`
- **Public ingress：** Cloudflare Tunnel，獨立於 CatDesk source 維護
- **目前已接受的 production source delta：** 只有兩個 Rust 檔：
  - `src/mcp.rs`
  - `src/workspace_tools.rs`
- **OpenAI MCP Apps 相容 candidate：** 可額外修改 `src/widget/catdesk_dashboard.html`，但僅限 ChatGPT entrypoint 所必需的最小標準 UI lifecycle / result bridge。

除非未來 upstream 架構改變、且確實需要不同的最小實作，其他 CatDesk source 都應保持與 upstream 一致。OpenAI 相容層必須維持 additive：Standard MCP、Hermes client、transport 與 filesystem semantics 都不得依賴它。

## 為什麼需要這個 private repo

官方 CatDesk 的檔案工具主要受 workspace 邊界限制；本機 production 還需要受控地讀取部分 Mac 路徑與外接硬碟。

目前政策：

```text
WORKSPACE_ROOT=/Users/hong/workspace
CATDESK_READ_ROOTS=/Users/hong:/Volumes/ExpansionDrive
CATDESK_WRITE_ROOTS=/Volumes/ExpansionDrive
```

必要行為：

- workspace 原本讀寫正常；
- 設定在 read roots 的路徑可 read/search/list；
- 設定在 write roots 的路徑可 write/edit/delete/move；
- read 權限不能自動變成 write 權限；
- canonicalization 必須阻擋 traversal 與 symlink escape；
- 超出允許 roots 的路徑必須拒絕；
- `/Volumes/ExpansionDrive` 必須能真實讀寫。

外部檔案路徑契約仍是主要長期 CatDesk source customization。另允許一個可選、薄層的 OpenAI MCP Apps 相容能力：僅包含 namespaced OpenAI entrypoint metadata，以及 ChatGPT 所需的最小 widget lifecycle / result bridge。不得把 `openai/mcp-extensions` 整包 vendor 進 repo、不得新增平行 framework，也不得讓 Standard MCP / Hermes 依賴這一層。

## 明確不屬於 CatDesk source custom

以下功能不得為了方便又塞回 CatDesk core：

- Cloudflare Tunnel；
- launchd service 管理；
- activation / restart orchestration；
- TokenBar 整合；
- CatDesk usage ledger / telemetry；
- pricing-model tracking；
- Hermes / Kanban 整合。

未來 TokenBar 若真的需要 CatDesk usage，優先在 TokenBar private repo 或外部 read-only bridge 處理。除非沒有任何合理外部介面，而且漢秦哥明確同意，否則不要再把 usage ledger 加回 CatDesk `state.rs`。

## Source-of-truth 固定順序

未來 release 順序必須固定如下：

```text
Xeift/CatDesk upstream stable release
        ↓
HCH725/CatDesk-custom private repo
  reviewed main + accepted custom tag
        ↓
從 accepted tag 建 local release build
        ↓
runtime-next 簽署 / 驗證
        ↓
本機 stable production runtime
        ↓
post-activation acceptance
```

**任何新的 upstream 版本，都不得在 private repo 對齊、push、tag 驗證完成以前，直接先部署到本機。**

Private repo 才是 downstream source of truth；本機 Mac 是 deployment target，不是 source repository。

## 維護角色

1. 漢秦哥決定是否採用 upstream 新版本。
2. ChatGPT 檢視 release、控制範圍並避免過度工程。
3. Hermes `default` 可以負責實作。
4. Hermes `auditor` 可以做獨立審查；也可直接呼叫 `auditor` profile 審查 frozen candidate。
5. 不得為了讓 CatDesk audit lane 工作，而去擴張或修改 Hermes runtime。
6. ChatGPT 負責確認 private repo、部署及 production 實際行為。

README 是 behavioral contract。
`skills/catdesk-release-update/SKILL.md` 是操作程序。

## 每次 upstream 更新的必要流程

當 Xeift/CatDesk 發布新的 stable release：

1. Fetch `origin` 與 `upstream`，確認 local `main == origin/main`，worktree clean。
2. 閱讀 upstream release notes，盤點 API/schema/runtime 變化。
3. 從新的 upstream stable tag/commit 建立乾淨 candidate。
4. 只移植仍然必要的 external roots 能力；若 OpenAI MCP Apps 相容層仍有必要，也只保留其最小實作。不得整份複製舊 custom source。
5. 若 upstream 已吸收某項行為，直接刪掉 downstream 實作。
6. 檢查 downstream source diff。預設為 `src/mcp.rs` 與 `src/workspace_tools.rs`；只有在 OpenAI MCP Apps 相容層啟用時，才額外允許 `src/widget/catdesk_dashboard.html`，且 review record 必須證明改動僅限標準 UI lifecycle / result handling。其他 source file 一律需要明確理由。
7. 執行 source validation：
   - `cargo fmt --all -- --check`
   - `cargo check --all-targets`
   - 完整 Rust tests
   - read/write roots focused tests
   - traversal / symlink escape tests
   - 真實 `/Volumes/ExpansionDrive` read/write test
   - `git diff --check`
8. 將 accepted candidate 整合進 **本 private repo**；行為或 release 狀態有變更時才同步 README / skill。
9. 建立下一個 `vX.Y.Z-custom.N` tag，並把 **`main` 與 tag 都 push 到 `origin`**。
10. 再 read back `origin/main` 與 remote tag，確認都指向預期 accepted commit。
11. **只有步驟 10 完成後，才能開始本機 production deployment。**
12. 從 private repo accepted tag build local release binary。
13. 將 binary stage/sign 到 `runtime-next`，沿用 `com.hong.catdesk`，先跑 read-only preflight，再使用 canonical one-shot activation controller。
14. ChatGPT 重連後做 post-activation acceptance：
    - MCP tools；
    - Mac 外部路徑 read；
    - ExpansionDrive write/read/delete；
    - write-root denial；
    - browser bridge；
    - Cloudflare continuity。
15. controller 建立的啟用前 backup 保留作 rollback source。Production-critical boundary 失敗就 rollback，不要再加新 infrastructure。

## macOS stable runtime

正式 production path：

```text
/Users/hong/.local/share/catdesk/runtime/bin/catdesk
```

必須維持 physical file，並沿用固定簽署身份：

```text
Identifier=com.hong.catdesk
Authority=CatDesk Local Code Signing
Designated Requirement:
identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"
```

launcher 只能指向 stable runtime path。

正式 activation helper：

```text
scripts/activate-stable-runtime.sh
```

它的責任刻意只有 process-level activation：backup、atomic promotion、一次 kickstart、replacement child 驗證、30 秒穩定性與 TCP 3200。不得修改 Cloudflare / TCC，也不得讀 MCP secret。

## Cloudflare

Cloudflare 是目前 public ingress，而且刻意與 CatDesk source 分離：

```text
ChatGPT
   ↓
Cloudflare Tunnel
   ↓
localhost:3200
   ↓
CatDesk
```

CatDesk upstream 更新不得因此換回 ngrok、修改 Cloudflare tunnel config，或把 Cloudflare 寫成 Rust source custom。

## 2026-09-27 thin-custom 對齊紀錄

Production thin candidate frozen revision：

```text
9679f5b08825b39cb5587d5363ea0faf5f530224
```

相對 upstream `v0.9.5`，source delta：

```text
src/mcp.rs             |  41 +++---
src/workspace_tools.rs | 364 +++++++++++++++++++++++++++++++++++++++++++++++-
2 files changed, 381 insertions(+), 24 deletions(-)
```

啟用前實測：

- `cargo fmt --check`：PASS
- `cargo check --all-targets`：PASS
- Rust tests：**250/250 PASS**
- 真實 ExpansionDrive focused test：PASS
- release build：PASS

2026-09-27 production activation：

- atomic runtime replacement：PASS
- stable codesign / DR：PASS
- replacement child：PASS
- 30 秒 triple stability：PASS
- TCP 3200：PASS
- ChatGPT MCP 重連：PASS
- Mac 外部路徑 read：PASS
- ExpansionDrive write/read/delete：PASS
- configured write roots 以外寫入：正確拒絕
- browser bridge：PASS
- Cloudflare continuity：PASS
- rollback backup：`~/.catdesk/activation/backups/20260927-170554-67118`

這次是漢秦哥明確批准 production cutover 後，才立即回頭把 private repo 對齊，因此屬於**一次性的歷史例外**。未來所有版本都必須遵守前述「private repo 先完成，才正式部署本機」順序。

## Repo hygiene

- 不得 commit runtime binary、`runtime-next`、activation backup、credential、tunnel secret、cookie、TCC database 或 local signing private key。
- upstream 已提供的功能，不要維護另一套 downstream implementation。
- 除非 CatDesk core 本身真的需要，不要加入 monitoring、retry、watchdog、compatibility 或 telemetry framework。
- deployment scripts 與 Rust source custom 必須概念分離。
- 不要為了追 upstream 而 force-push `main`；每次 upstream release 都以正常 downstream commit/tag 整合。

## Upstream attribution / License

本 repo 基於 Xeift/CatDesk，保留 upstream license 與 attribution：

https://github.com/Xeift/CatDesk
