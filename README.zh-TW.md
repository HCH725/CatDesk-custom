# CatDesk Custom

[English](README.md) | [繁體中文](README.zh-TW.md)

> **這是漢秦哥目前 production CatDesk 的 Private downstream repository。**
>
> 這個 repository **不是**單純複製官方 CatDesk，而是正式保存：
>
> **Xeift/CatDesk 官方穩定版 + 本機最小必要客製化 = production CatDesk**

## 專案用途

- **官方 upstream：** https://github.com/Xeift/CatDesk
- **Upstream source of truth：** `Xeift/CatDesk` 官方 stable tag
- **目前 upstream baseline：** `v0.7.0`
- **目前 upstream commit：** `cc5daf850cfa5bcd6cae8e414b9009eeeba0a6d8`
- **Downstream 版本命名：** `vX.Y.Z-custom.N`
- **已接受 downstream release：** `v0.5.0-custom.3`（不變，目前 production provenance）
- **Candidate：** `upgrade/v0.7.0` onto `v0.7.0`（待審，未接受，不做 production rollout）
- **Production source of truth：** 通過驗收與 audit 後的這個 private repository

未來更新時，**不能用乾淨 upstream checkout 直接取代本 repo**。新版必須保留下方記載的 downstream contract，同時保留新 upstream release 的功能。

## 維護角色與流程

維護流程固定保持簡單：

1. **漢秦哥**決定是否升級 CatDesk。
2. **ChatGPT**分析 upstream release、規劃更新方式並 review 結果。
3. **Hermes `default` profile**實際執行 port、build、test 與本機驗證。
4. **Hermes `auditor` profile**獨立驗證，不能由 default 自己宣告正確。
5. ChatGPT 判讀 audit 結果，決定 remediation 或 advance。
6. 若需要修補，由 Hermes `default` remediation，再重新 audit。

本 repo 用兩層定義 CatDesk 更新的 authority：

- **README（本檔）是 canonical behavioral contract** — 無論哪一版 release，production CatDesk 都必須維持的行為契約。
- **`skills/catdesk-release-update/SKILL.md`（repo-tracked）是 canonical operational procedure** — Hermes 實際執行更新的方式。

本機 Hermes runtime entrypoint

`~/.hermes/skills/software-development/catdesk-release-update/SKILL.md`

只是 symlink entrypoint，必須指向上面 repo-tracked skill。若 README 與 Skill 衝突，以 README 為準：立即停止 upgrade，先把 Skill 對齊 README，再繼續。

每次升級前，Hermes 必須先 fetch/sync 本 repo、確認 `origin/main`、讀完本 README 與 repo-tracked skill、確認 runtime skill entrypoint 指向 repo-tracked 檔案，然後才查目前 accepted `vX.Y.Z-custom.N` tag 與 rollback 版本。不得靠記憶或舊 worktree。

## 目前 downstream custom contract

### 1. Read / write roots 必須分離

Production CatDesk 在 upstream workspace boundary 之外，支援明確設定的額外讀寫 roots。

目前 production policy：

```text
WORKSPACE_ROOT=/Users/hong/workspace
CATDESK_READ_ROOTS=/Users/hong:/Volumes/ExpansionDrive
CATDESK_WRITE_ROOTS=/Volumes/ExpansionDrive
```

必須保留的語意：

- `WORKSPACE_ROOT` 仍是一般 workspace boundary。
- `CATDESK_READ_ROOTS` 只增加可讀取位置。
- `CATDESK_WRITE_ROOTS` 才增加可寫入、編輯、刪除，以及 move source / destination 的位置。
- **可讀絕對不能自動等於可寫。**
- 多個 root 必須遵循作業系統 path-list semantics。
- 未經明確批准與測試，不得把權限粗暴擴大成整個 home 或整顆磁碟。

### 2. Canonical path 安全邊界

所有 extra-root access 都必須維持安全檢查：

- 已存在的 candidate path 要 canonicalize。
- 尚不存在的 path，要先 canonicalize 最近的既存 parent，再做 boundary validation。
- traversal 不得逃出允許 roots。
- symlink 不得逃出允許 roots。
- read 與 write boundary 必須分開驗證。

### 3. Change tracking 必須使用 canonical target

Change tracking 必須以 canonicalized target 建立 snapshot，避免 external allowed roots、symlink、edit、delete、move 的 before/after diff 失真。

### 4. Command / move 必須使用正確的 write boundary

`src/mcp.rs` 的 downstream 行為必須持續區分：

- command/current working directory：只需要 read boundary；
- move source：需要 write permission；
- move destination：需要 write permission；
- write boundary 失敗時，要回報 write-root violation，而不是退化成一般 workspace error。

### 5. Append-only 本機 usage ledger

Production CatDesk 必須把既有 MCP token accounting 以最小化的本機 event ledger 暴露在 `~/.catdesk/usage.jsonl`，供下游 usage consumer 使用。

必須保留的語意：

- `config.toml` 既有累積 usage totals 繼續保存；ledger 是補充，不取代原本 totals。
- 每次記錄 MCP tool call 時 append 一行 JSONL，穩定欄位為 `eventId`、`timestampMs`、`inputTokens`、`outputTokens`、`bucket`、`pricingModel`。
- `pricingModel` 記錄供下游估算成本使用的 ChatGPT 模型 identity；CatDesk 在 UI 仍維持獨立的 `catdesk-mcp` usage source。ChatGPT runtime 換新模型時只更新版本化的 `CURRENT_USAGE_PRICING_MODEL`，不得從 accounting `bucket` 猜測模型。
- `eventId` 必須對每個 recorded event 唯一；即使 ledger row 被移動或重排，也要維持下游 dedup 的穩定 identity。
- 每行不要重複保存可推導的 `totalTokens`。
- Production 假設 CatDesk daemon 是 ledger 唯一 writer；若 crash 留下截斷的最後一行，下次 append 必須先補 newline 隔離殘片，再寫入下一個完整 event。
- ledger 寫入失敗只能記 warning，不得讓 MCP tool response 跟著失敗。
- Unix-like 系統中新建立的 ledger 檔案必須為使用者私有（`0600`）。
- 不得為 ledger 上線以前的累積 usage 虛構 timestamp 歷史；舊累積 totals 繼續留在 `config.toml`。
- `usage.jsonl` 是 runtime state，絕對不能 commit 到本 repository。

### 6. Upstream 新功能不能被 custom 覆蓋掉

Downstream port 不能為了保留舊 custom 而把新版 upstream 功能洗掉。

目前 `v0.7.0` baseline 至少要保留：

- `read` 支援 `paths` array；
- 每批最多 32 個 paths；
- upstream batch read size limit；
- `poll_command` long-poll 行為與 documented wait limit；
- cursor-based incremental command output；
- job 已 terminal 但 `hasMoreOutput=true` 時仍必須繼續 drain buffered output；
- `v0.5.0` 之前已導入的 connector bootstrap/widget completion 行為；
- Traditional Chinese mode selection 與持久化的 UI language preference；
- opt-in macOS Terminal.app profile flow 與持久化偏好；
- macOS 在標準 `/Applications` 與 `~/Applications` App bundle 中的 Chromium-family detection；
- upstream `v0.7.0` session handoff（`create_handoff`）含 workspace-local storage 與 ChatGPT Library recovery（原生實作，`src/handoff.rs` 無 downstream 客製）；
- upstream Linux sandbox SSH authentication 行為。

每次新 upstream release 都必須重新閱讀 release notes，動態產生 release-specific smoke checks。

## 目前 custom source scope

`v0.7.0` candidate downstream 目前只修改 upstream 的四個 source files：

```text
src/change_tracking/mod.rs
src/mcp.rs
src/state.rs
src/workspace_tools.rs
```

這三個檔名不是永久規則。未來 upstream 架構可能改變，屆時可能需要更少、不同，甚至零個修改。要保存的是 **behavioral contract**，不是舊版檔案配置。

## 穩定 macOS runtime 身份與部署契約（Phase B — PRODUCTION_ACCEPTED）

### Root cause

macOS TCC 以 binary 的有效身份（filesystem path、code signature、CDHash、Designated Requirement）綁定權限。過去部署使用版本化路徑 `~/.local/share/catdesk/<version>-custom/bin/catdesk` 搭配 **ad-hoc** 簽署（`Identifier=catdesk-…`、`Signature=adhoc`、`CDHash=aaa5b…`），每次新版都呈現全新的 TCC 身份（path + ad-hoc CDHash/DR），不會繼承舊授權，導致 TCC rows 孤兒化、每次都要重新彈窗。

已由 ad-hoc production binary `0.5.0-custom.3`（`CDHash=aaa5b23ec711a827b8f981a92f7fc5c306df44ea`、`Identifier=catdesk-e6cd98f31dbf91fd`）對比任何穩定簽署 binary 確認此原因。

### 部署契約（canonical）

每次 promotion 都必須走且只走這條鏈路：

```text
accepted tag vX.Y.Z-custom.N
  → versioned artifact ~/.local/share/catdesk/<version>-custom/bin/catdesk（build provenance）
  → 以穩定簽署身份 com.hong.catdesk 重新簽署
  → 實體穩定 runtime ~/.local/share/catdesk/runtime/bin/catdesk（launcher 唯一目標）
  → launcher exec: spawn /Users/hong/.local/share/catdesk/runtime/bin/catdesk
  → production acceptance（ephemeral job + triple stability + MCP/Cloudflare/roots）
```

未來升級必須遵循 GitHub-first → accepted tag → versioned artifact → stable sign/copy → stable runtime → production acceptance；**不可直接在 production 執行 `git pull`**。

規則：

- `runtime/bin/catdesk` 必須是 **實體檔案**，永遠不是 symlink。所有檢查（`test -L`、`codesign -dv`、`shasum -a 256`）都要對檔案本體執行。
- Rollback 是把 **前一個 accepted artifact 重新簽署並複製** 到同一個 `runtime/bin/catdesk` 路徑。`runtime` 啟用後，launcher 永遠不再指回任何版本化路徑。
- 驗證階段使用 `~/.local/share/catdesk/runtime-next/bin/catdesk`（實體複製 + 簽署 + 驗證），通過後才 promotion 到 `runtime/bin`。在通過所有 gate 與獨立 audit 前，不得修改 `runtime/bin` 或 launcher。
- `runtime/` 與 `runtime-next/` 是 production runtime state，**絕對不能 commit**。

> **Canonical / current production（Phase B — PRODUCTION_ACCEPTED）：** launcher 的**唯一**目標是實體穩定 runtime `/Users/hong/.local/share/catdesk/runtime/bin/catdesk`（簽署 `Identifier=com.hong.catdesk`、`DR=identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`）。版本化產物 `~/.local/share/catdesk/<version>-custom/bin/catdesk` 僅保留為 **provenance / rollback source**，**不得**再作為 launcher target。歷史備註：Phase B 啟用前，實際運行的 child 曾暫時為 `/Users/hong/.local/share/catdesk/0.5.0-custom.3/bin/catdesk`（版本化路徑、ad-hoc `CDHash=aaa5b23ec711a827b8f981a92f7fc5c306df44ea`、`Identifier=catdesk-e6cd98f31dbf91fd`）—— 該狀態已退役，不得視為當前 production。

### 穩定簽署身份（一次性本機 bootstrap）

讓契約得以 TCC-persistent 的穩定身份為：

- **Name：** `CatDesk Local Code Signing`
- **Identifier：** `com.hong.catdesk`（`codesign --identifier com.hong.catdesk`）
- **Certificate SHA-1（non-secret）：** `7F453106476B0DA6B2FEDBC4BC6F81B8C9ACA51A`
- **Certificate SHA-256（non-secret）：** `B5705686206499D677B6AF20C470D7C4C7A3E51BE1203738F2DA3F9BC8D3B043`
- **Subject（non-secret）：** `CN=CatDesk Local Code Signing, OU=CatDesk Local, O=Hong Local, C=TW`
- **Expiry（non-secret）：** `2028-12-04`
- **Expected DR（non-secret）：** `identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`
- **TeamIdentifier：** `not set`（本機 self-signed）

Bootstrap 是在該 Mac 上 **一次性本機操作** 建立 Keychain certificate/keypair。Certificate 與 private key 是 **本機 secret，絕對不得 commit 到 Git、不得寫入本 repository、不得留下 log**（無 p12、無 password、無原始 key material —— 僅記錄上述 non-secret fingerprint/subject/expiry）。在另一台機器重建或輪替身份時，必須保留相同 `Identifier`，且不得視為 repo 內資產。

### 身份實證（跨 binary DR 穩定）

以此身份簽署兩份不同內容的 binary，已獨立驗證 DR 完全相同、即使 hash 不同：

- **A（0.5.0-custom.2 內容）簽署後：** `SHA256=617328bd33dfe7b5d02e4e722c1d0b6db4fdeb3b01b2c096b1b81356bb5f372a`、`CDHash=8ec4dd1bfa00d343aafb80a699a3e265ed2e23f7`、`Identifier=com.hong.catdesk`、`Authority=CatDesk Local Code Signing`
- **B（0.5.0-custom.3 內容）簽署後：** `SHA256=7e840ab9fc32f38adfa4fb187f92833c24c68fba4881410530053007d83023ac`、`CDHash=f0f90badc43c2851273dfb099d5b7a6b306236ea`、`Identifier=com.hong.catdesk`、`Authority=CatDesk Local Code Signing`
- **兩者皆：** `Designated Requirement = identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"` 且 `codesign --verify --strict --verbose=4` = `valid on disk` + `satisfies its Designated Requirement`。

這證明穩定 certificate + 穩定 identifier 能在 binary 內容變動下維持 **穩定 DR**，即 TCC-persistence 的必要條件。由目前 accepted `0.5.0-custom.3` 複製並簽署至 `runtime-next/bin/catdesk` 的實體 staging 亦必須呈現相同 DR（目前 staging `CDHash=f0f90badc43c2851273dfb099d5b7a6b306236ea`、`Identifier=com.hong.catdesk`、DR 同上）。

### 驗證門檻（不得只看 `find-identity` 文字）

`security find-identity -v -p codesigning` 可能對此本機 self-signed certificate 顯示 `CSSMERR_TP_NOT_TRUSTED`。此 warning 僅為 **資訊提示，不是 blocker** —— 真正的 gate 是 `codesign --verify --strict` 與 DR 滿足度。

每次 deploy/stage 都必須以以下指令為 gate：

```bash
codesign --verify --strict --verbose=4 /Users/hong/.local/share/catdesk/runtime-next/bin/catdesk  # 或 runtime/bin/catdesk
codesign -dv --verbose=4 /path/to/binary  # Identifier=com.hong.catdesk, Authority=CatDesk Local Code Signing, CDHash 吻合預期
codesign -d -r - /path/to/binary          # designated => identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"
shasum -a 256 /path/to/binary
test ! -L /path/to/binary                  # 必須是實體檔案
```

不得僅以 `find-identity` 列表文字作為通過依據；必須核對實際 `codesign` 驗證與預期 fingerprint/identifier/DR。Trust-policy 文字差異不代表簽署失效。

### TCC 清理政策

舊版本化路徑的 TCC rows（例如 `0.5.0-custom.3` ad-hoc 路徑）可保留為 **stale cosmetic rows**，直到使用者選擇一次性整理。**禁止** 以 `sqlite3` 或任何直接 DB 寫入方式修改 `~/Library/Application Support/com.apple.TCC/TCC.db` —— 該路徑不被支援且可能毀損 TCC。**不得**為 CatDesk 清理而執行或推薦任何 `tccutil reset`（全域或針對特定 service，例如 `All`、`Accessibility`/`ScreenCapture`/`Automation`）；一般版本更新絕不執行任何 TCC 清理/重置。若使用者要清理 stale entries，**僅建議**使用受支援的 System Settings UI（**System Settings → Privacy & Security**）檢視/移除舊版本化路徑的 stale entry，必要時再從穩定的 `runtime` 路徑重新互動授權。除非已在實機上對「該特定 client/service」的 `tccutil reset <service> <client>` 精確作用範圍完成獨立實證，且明確知道不會一併重置當前 stable runtime 的權限，否則不得為 CatDesk 清理推薦或執行任何 `tccutil reset`。清理 **不是 release gate、不是 production blocker**。

### TCC 遷移lesson（一次性 bootstrap）

從舊 ad-hoc／版本化路徑（`~/.local/share/catdesk/<version>-custom/bin/catdesk`，ad-hoc `Identifier=catdesk-…`）第一次遷移到穩定簽署 runtime（`~/.local/share/catdesk/runtime/bin/catdesk`，`Identifier=com.hong.catdesk`、`DR=identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`）時，macOS 可能彈出 **一次新的權限／TCC 授權**。這是 **一次性 bootstrap** —— 使用者授權後，未來 accepted versions 必須 **複製／簽署到相同實體 `runtime/bin/catdesk` 路徑、沿用同一 signing identity／Identifier／DR**，不得把 launcher 改回版本化路徑，否則每版都會新增 TCC client。

### Post-activation acceptance 契約（PRODUCTION_ACCEPTED）

Phase B 的 `PRODUCTION_ACCEPTED` 僅在以下全部通過後授予（記錄為契約，不硬寫 PID）：

- **Ephemeral activation job：** `launchctl bootstrap` one-shot 僅執行 **一次**（`runs=1`、`exit 0`），結束後由重連的 ChatGPT 執行 `launchctl bootout` 清理。
- **Process-level activation：** 精確 child 取代（`PPID==wrapper` + `exe==/Users/hong/.local/share/catdesk/runtime/bin/catdesk`）、**30 秒 triple stability**（wrapper PID + `runs` + stable child PID 皆不變，`PPID`/`exe` 仍穩定）與 `nc -z 127.0.0.1 3200` TCP 成功。
- **Post-activation acceptance（重連後 ChatGPT）：** MCP `catdesk_instruction` discover + `catdesk_command`／`search`／`write`／`delete`、ExpansionDrive 讀寫、**write-root denial** 與 **outside-read-root denial**（path-boundary 驗證）以及 **Cloudflare continuity** 全部 PASS，才算 `PRODUCTION_ACCEPTED`。

Launcher 唯一目標為穩定 runtime；穩定 `codesign Identifier=com.hong.catdesk` 且同一 local certificate／DR；Cloudflare tunnel 不變；read／write roots 契約不變。

### Troubleshooting 備註 — 專用 `read` 工具 schema mismatch

專用 `read` 工具的 schema `path` 與 runtime 實際 `paths`／`CATDESK_READ_ROOTS` 不一致，為 **既有、非阻塞的 tool-surface issue**，不是穩定 runtime 或 TCC 的 regression。已另行追蹤，不影響 Phase B 的 `PRODUCTION_ACCEPTED` 契約，亦不得擴張為新 framework。

## Hermes 必須遵守的更新流程

當漢秦哥批准評估新的 stable CatDesk release：

1. 先 fetch/sync 本 repo，確認 local `main` 與 `origin/main` 一致，再讀本 README 與 repo-tracked `skills/catdesk-release-update/SKILL.md`。
2. 確認 local runtime skill entrypoint 指向 repo-tracked skill，再以 tag/README 讀出目前 accepted downstream tag（`vX.Y.Z-custom.N`）、repo clean state 與 rollback 版本；不得靠記憶或舊 worktree。
3. Fetch 官方 upstream tags，記錄新 tag、commit、release notes、API/schema/runtime changes。
4. 一律從 **新的 upstream stable tag** 開始，不得從舊 custom source 整份複製。
5. 比較目前 accepted downstream behavior 與新版 upstream architecture。
6. 只 port **仍然必要的最小 custom behavior**；禁止把舊 source file 整份蓋到新版。
7. 保留新版 upstream 的所有適用功能，custom 必須配合新版架構重新適配。
8. build 前先跑 formatting、upstream tests 與 downstream boundary/security tests。
9. 建立 custom production artifact，並分開記錄：
   - upstream tag / commit；
   - downstream diff；
   - upstream official artifact digest（如適用）；
   - custom binary SHA-256。
10. Custom binary 必須安裝到版本化路徑，例如 `~/.local/share/catdesk/<version>-custom/bin/catdesk`。
11. 前一個 accepted custom 版本必須保留做 rollback；deploy 前先備份 launcher / plist。
12. CatDesk binary update 只改必要部分，production roots/environment 要保留。**CatDesk 更新不得順便重建或修改 Cloudflare tunnel。**
13. 只重啟 CatDesk service，再跑 production-surface acceptance。
14. ExpansionDrive I/O、path security 或必要 upstream feature 任一失敗，立刻 rollback，狀態只能是 **PARTIAL/FAIL**，不能宣告 PASS。
15. 必須交給 `auditor` 做獨立 review。
16. 全部通過與 audit 後，才 merge 到 `main`，並建立新的 `vX.Y.Z-custom.N` tag。

## Production activation 事故防線

2026-08-31 `v0.5.0-custom.1` prepare/rollback 事故確立以下必要控制：

- 絕不能把 activation helper 提交成 `KeepAlive` launchd service；即使 binary 本身健康，仍可能形成無限 restart／瀏覽器重開迴圈。
- activation 前必須以 `launchctl print`、`launchctl list` 與 plist registration 證據確認當下 owning launchd domain。不得硬編碼 `gui/<uid>` 或 `user/<uid>`；在猜測 domain 找不到 service 是 domain/registration mismatch，不是 v0.5 runtime regression 的證據。
- foreground 或 one-shot controller 必須在 CatDesk process tree 外：先快照 launcher/plist hash，只切換 launcher target，提供自足的 backup/rollback recipe（launcher/plist 快照 + provenance），且僅 kickstart CatDesk。Controller **never auto-rolls-back** —— rollback 由外部 ChatGPT 明確決策。
- `launchctl kickstart -k` 本來就會終止 child；`SIGTERM` 與 Expect `spawn id ... not open` 是重啟證據，不是新 binary crash 的證明。
- restart 後 controller 只驗 process-level gates：精確 replacement child（PPID==wrapper + exe==stable runtime）、30s triple stability（wrapper PID + `runs` + stable child PID 皆不變且 PPID/exe 仍穩定）以及 `nc -z 127.0.0.1 3200`。health/discover、root invariants 與 Cloudflare continuity 屬於重連後 ChatGPT 的 **post-activation acceptance**，不是 controller gate。
- local MCP 與 public ingress 的驗證屬於 post-activation acceptance（重連後 ChatGPT 驗收）。Cloudflare 是 active public path 時，stale/legacy ngrok endpoint 的 quota/error 只能記為 stale probe：不是 production ingress evidence，也不得驅動 rollback 或任何 Cloudflare 變更。
- 兩階段就緒：controller preflight PASS 為 `READY_FOR_PROCESS_ACTIVATION`（可進入 activation）；controller success（精確 child + 30s triple + TCP PASS，或冪等 `ALREADY_ACTIVE` PASS）為 `READY_FOR_POST_ACTIVATION_ACCEPTANCE`；重連後 ChatGPT 驗 MCP/command/Cloudflare/roots 全 PASS 才算 `PRODUCTION_ACCEPTED`。

## 穩定 runtime Phase B 控制器（2026-09-01 — remediation，僅 process-level activation）

首次 Phase B 失敗的兩個 root cause：（1）`launchctl submit` job 被再次分發、失控重跑；（2）controller 寫死 `/health`、`/mcp` 探針，實際 secret route 回 404 卻被誤判為 binary 健康失敗。

Canonical Phase B controller 契約（僅 process-level activation）：

- Controller 永遠不取得 MCP secret slug、不做 MCP discover / command execution，不讀 `~/.catdesk/config.toml` 的 slug/token。
- `/health`、`/mcp` 不可寫死；HTTP 404 不是 controller 的 binary-health failure，secret route 不在 controller 範圍內。
- `launchctl submit` 禁止用於 activation one-shot，會被 launchd 再次分發。
- 遠端執行必須脫離 CatDesk process tree 時（ChatGPT→CatDesk→Hermes，前景 controller 會隨 CatDesk 一起消失），使用經過無害 `run=1` probe 驗證的 **ephemeral `launchctl bootstrap` plist**：unique label `com.hong.catdesk.*`、`RunAtLoad=true`、`KeepAlive=false`、無 `StartInterval`/`WatchPaths`/`StartCalendarInterval`，plist 置於受限 `~/.catdesk/activation/`（0700 目錄、0600 檔案），絕不放入 `~/Library/LaunchAgents`。bootstrap 後該 job 必須只執行一次；清理由重連後的 ChatGPT 執行 `launchctl bootout <domain>/<label>`（或 `bootout <domain> <plist>`），controller 不得自行重啟。
- Single-flight 使用 `/usr/bin/lockf` 的 `lockf -k -t 0` wrapper re-exec（macOS 無 `flock`），第二個並發實例必須立即 busy 失敗（例如 75、`already locked`），不排隊。
- Controller 最多只允許 **一次** `launchctl kickstart -k <resolved-domain>/com.hong.catdesk`，無 retry loop、無 auto-rollback；任一 gate 失敗即非 0 退出，保留 private backup，外部分由 ChatGPT 判斷。
- Controller 的 gates 僅為 process-level：target path 為實體檔案（非 symlink）、`codesign Identifier=com.hong.catdesk` 與 `DR` 有效（`identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`）、動態解析 launchd domain（`gui/<uid>` 或 `user/<uid>`，不 hard-code）、launcher/plist 存在、`nc`/`TCP` 工具可用（`nc -z 127.0.0.1 3200`）；不得 `curl` `/health`/`/mcp`，不得讀/輸出任何 slug。
- `--activate` 後的 replacement 驗證為精確檢查：先經 `launchctl print <domain>/com.hong.catdesk` 取得 wrapper PID，再以 `ps -axo pid=,ppid=,command=` 找 PPID==wrapper PID 且第一 exe token 精確等於 `$STABLE_RUNTIME` 的 child；加上重啟後 triple 30 秒穩定性（wrapper PID + `runs` + stable child PID 皆不變且 PPID/exe 仍穩定）與 `nc -z 127.0.0.1 3200` 成功。冪等：若 launcher 已精確穩定且 child 已精確穩定則跳過 kickstart，直接做 `ALREADY_ACTIVE` 三重穩定 + TCP。
- 啟用後的 **acceptance**（MCP discover、command execution、Cloudflare continuity、read/write roots/boundaries、ledger）由 ChatGPT 以 `catdesk_instruction` 重連後另行驗收；失敗由外部判斷，rollback 由外部明確決定（將前一 accepted versioned artifact 重新簽署/複製回同一 `runtime/bin/catdesk` 路徑）。
- 不可在 repository、skill、script 輸出或 logs 中記錄任何 secret slug、token 或 tunnel credential。

Canonical controller 產物：`scripts/activate-stable-runtime.sh`（預設 `--preflight`，需顯式 `--activate`）。遠端脫離所需的 ephemeral bootstrap 流程記載於此與 `skills/catdesk-release-update/SKILL.md`，不產生 daemon/service。

遠端 activation 的 ephemeral bootstrap（當 controller 必須比 CatDesk 活得更久時）：

```bash
# 1. 已有無害 run=1 probe 證實此 pattern 的語意 — 不要用 launchctl submit。
# 2. 建受限 staging：umask 077; mkdir -p ~/.catdesk/activation（0700）
# 3. 寫 plist 到 ~/.catdesk/activation/com.hong.catdesk.activate.<timestamp>.plist（0600）：
#    Label=com.hong.catdesk.activate.<timestamp>，ProgramArguments=[/path/to/scripts/activate-stable-runtime.sh --activate]，
#    RunAtLoad=true，KeepAlive=false，無 StartInterval/WatchPaths/StartCalendarInterval
# 4. 動態解析 domain：gui/<uid> 若 launchctl print gui/<uid>/com.hong.catdesk 成功否則 user/<uid>
# 5. launchctl bootstrap <domain> <plist>（unique label，僅跑一次）
# 6. 重連後 ChatGPT 驗 replacement + 30 秒穩定 + nc -z 127.0.0.1 3200，再做 MCP/Cloudflare acceptance
# 7. 清理：launchctl bootout <domain>/<label>（或 bootout <domain> <plist>）；controller 永不自行 bootout/重啟
```

## Acceptance checklist

能編譯不代表升級成功。至少必須確認：

- formatting pass；
- upstream test suite pass；
- workspace read/write/edit/delete/search pass；
- 明確允許的 external read pass；
- 明確允許的 external write/edit/delete pass；
- read-only external root 無法寫入；
- traversal / symlink escape 被拒絕；
- canonical/external target 的 change tracking 正確；
- 新 release 的 API/schema/runtime behavior 正常；
- launchd active child 指向正確的 production binary — **canonical / current production（Phase B — PRODUCTION_ACCEPTED）：** 必須是實體穩定 runtime `/Users/hong/.local/share/catdesk/runtime/bin/catdesk`（launcher 唯一目標；版本化產物僅為 provenance/rollback source，不得作 launcher target）；
- CatDesk 沒有 crash loop；
- `/Volumes/ExpansionDrive` write/read/delete acceptance pass；
- Cloudflare tunnel continuity 不受影響；
- 所有測試產生的暫存檔都清除。

## Provenance 規則

Upstream 與 downstream artifact identity 必須分開：

- official upstream digest 只代表官方 artifact；
- custom binary digest 才代表本機 build 的 downstream production artifact；
- 官方 checksum 成功，不代表官方 binary 已包含本 repo 的 custom contract；
- 每次正式 production custom build 都要由 accepted downstream Git tag 綁定 source-level provenance。

## 絕對不能 commit 的內容

這個 repo 只保存 source 與 documentation，不保存 production runtime state。

禁止提交：

- API keys、access tokens、cookies、credentials、tunnel secrets、MCP path secrets；
- `~/.catdesk/config.toml` 或任何包含真實 credential 的 production config；
- 真實 production launchd plist / launch wrapper；
- Cloudflare/ngrok credential 或 tunnel config；
- runtime logs、`~/.catdesk/usage.jsonl`、restart markers、verification output、command job state、generated mascot/state files；
- `target/`、compiled binaries、`.dSYM`、backup、temporary build output、installed production binary；
- 把 secrets 複製到 examples、issues、commit messages 或 release notes。

未來若需要文件化 deployment config，只能提供 sanitized example 與 placeholder。

## Git remotes

預期 remote layout：

```text
origin   -> private downstream repository (HCH725/CatDesk-custom)
upstream -> official public repository (Xeift/CatDesk)
```

不要為了跟 upstream 對齊而 force-push `main`。Upstream 更新一律視為一次新的、需要 review 的 downstream release update。

## Build 與 test

使用 upstream Rust toolchain 與 project instructions。不要把任何 upstream 純格式 drift 帶入 downstream。對四個 downstream custom Rust files 做 scoped rustfmt/check；本 candidate 實測（`cargo test`：228 passed、0 failed；`cargo test --release`：228 passed、0 failed）：

```bash
rustfmt --edition 2024 --check src/change_tracking/mod.rs src/mcp.rs src/state.rs src/workspace_tools.rs
cargo check
cargo test
cargo test --release
cargo build --release
```

本 candidate 的 `src/handoff.rs` 與 upstream `v0.7.0` 完全一致（原生 `create_handoff`/Library recovery，無 downstream 客製）。Release-specific 與 downstream boundary tests 是額外要求，不能取代 upstream test suite。

## License 與 upstream attribution

本 downstream repository 保留 upstream MIT License 與原 copyright notice。CatDesk 原始專案由 `xeift.eth` / Xeift 開發：

https://github.com/Xeift/CatDesk

這個 private repository 的目的只是保存漢秦哥 production environment 所需的本機 custom modifications，以及未來每次升級的可追溯歷史。
