# CatDesk Custom

[English](README.md) | [繁體中文](README.zh-TW.md)

> **Private downstream repository for the production CatDesk installation used in Hanqin-ge's environment.**
>
> This repository is **not** a clean mirror of upstream CatDesk. It is the authoritative source for:
>
> **official Xeift/CatDesk stable release + the smallest required downstream customizations = production CatDesk**

## Repository purpose

- **Upstream project:** https://github.com/Xeift/CatDesk
- **Upstream source of truth:** official stable tags from `Xeift/CatDesk`
- **Accepted production baseline (currently deployed):** `v0.9.0`
- **Accepted upstream commit:** `37197b9f9530baa6634e32365be99ca78d9373cc`
- **Downstream release naming:** `vX.Y.Z-custom.N`
- **Accepted downstream release:** `v0.9.0-custom.1` (**PRODUCTION_ACCEPTED**, source-level provenance commit `495893ed95f39d997177f516eb69dae632966324`)
- **Official upstream macOS arm64 artifact SHA256 (v0.9.0):** `4d95fca3945978b78afd45ca13bf7c6aad0dddf334c5338b54e530b7fbcacf06`
- **Downstream versioned arm64 artifact SHA256 (v0.9.0-custom.1):** `00e274be65a10466a80ba0cecd4b32c95ae95f0fc0a296e50b63a3529a5a601d`
- **Current production runtime:** `/Users/hong/.local/share/catdesk/runtime/bin/catdesk` (stable-signed SHA256 `1b1ea9c4173cb16ddc3019ea5a0451829819971f731487ce281437faee8eb798`)
- **Previous accepted rollback release:** `v0.7.0-custom.1` (retained as rollback source; versioned artifact SHA256 `33593e1c33818dacabc6fee8a90923cec5e4376d974807d9c416a7a677ab006d`)
- **Production source of truth:** this private repository after a downstream release has passed acceptance and audit

### Accepted release record — `v0.9.0-custom.1` (2026-09-17)

- **Baseline:** upstream `v0.9.0` (tag object `2f6037e479bd7467d6f60dc56e0e114186a03be8`, commit `37197b9f9530baa6634e32365be99ca78d9373cc`); frozen candidate `d1ce2948e8230f0ec7f843cdfb1522e3e44d59a1`, merged as `495893e`.
- **History note:** sibling commit `266f107` (standing-rules update to `skills/catdesk-release-update/SKILL.md`, written on the agent side during this upgrade) is **deliberately retained** by owner decision. It caused the pre-audit revision drift that the re-freeze to `d1ce294` resolved; its content passed the credential scan and the independent re-audit, and it is part of this release's history.
- **Independent audits:** pre-activation audit FAIL (card `t_dc033b89`) → remediation commit `d1ce294` → re-audit **PASS** (`t_03492b4d`: F1–F7 all pass, 239 debug/release tests, activation harness T1–T4, credential scan all zero, production untouched during audit).
- **Activation (2026-09-17 06:25:55):** content-identity upgrade path (no `ALREADY_ACTIVE` false positive), atomic rename promotion, exactly one `kickstart -k`, replacement child PID change (`1002` → `51977`), 30s triple stability, `nc -z 127.0.0.1 3200` PASS; launcher/plist hashes unchanged; Cloudflare untouched; backup `~/.catdesk/activation/backups/20260917-062555-51896`.
- **Post-activation acceptance (reconnected ChatGPT):** PASS — MCP discover/command/search/write/delete, workspace and ExpansionDrive CRUD, write-root and outside-read-root denials, usage ledger continuity (16374 → 16512 rows, stable `eventId`/`timestampMs` schema), Cloudflare continuity.
- **Custom source scope:** `src/mcp.rs`, `src/state.rs`, `src/workspace_tools.rs`. `src/change_tracking/mod.rs`, `src/handoff.rs` and `src/linux_sandbox.rs` are upstream-identical in this release. `src/change_tracking/mod.rs` became upstream-identical because upstream `v0.8.0` `normalize_scope_paths` plus the downstream canonicalizing resolvers absorb the previous 7-line target-canonicalize custom; contract §3 is locked by the downstream boundary test `external_root_targets_keep_accurate_before_after_tracking`.
- **Verification (measured):** scoped `rustfmt --edition 2024 --check` pass; `cargo check --all-targets` pass; `cargo test` 239 passed / 0 failed; `cargo test --release` 239 passed / 0 failed; `scripts/tests/activate-controller-regression.sh` PASS (T1–T4).
- **Rollback source:** previous accepted artifact `~/.local/share/catdesk/0.7.0-custom.1/bin/catdesk`, re-signed as `com.hong.catdesk` and atomically replaced into the same `runtime/bin/catdesk` path.

Do **not** replace this repository with a fresh upstream checkout. Future updates must preserve the downstream contract documented below while retaining all relevant upstream release behavior.

## Ownership and operating model

The maintenance workflow is intentionally simple:

1. **Hanqin-ge** decides whether a CatDesk upgrade should proceed.
2. **ChatGPT** reviews the upstream release, plans the update, and reviews the result.
3. **Hermes `default` profile** performs the implementation and local verification.
4. **Hermes `auditor` profile** independently checks the result.
5. ChatGPT reviews audit findings and decides whether to remediate or advance.
6. Hermes `default` performs remediation if required, followed by another independent audit.

This repository defines the CatDesk update authority in two layers:

- **README (this file) is the canonical behavioral contract** — what must remain true about production CatDesk regardless of release.
- **`skills/catdesk-release-update/SKILL.md` (repo-tracked) is the canonical operational procedure** — how Hermes performs an update.

The Hermes runtime entrypoint

`~/.hermes/skills/software-development/catdesk-release-update/SKILL.md`

is only a symlink entrypoint and must resolve to the repo-tracked skill above. If the README and the skill conflict, the README wins: stop the upgrade, reconcile the skill with the README, and only then continue.

Before every upgrade, Hermes must fetch/sync this repository, confirm `origin/main`, read this README and the repo-tracked skill, confirm the runtime skill entrypoint resolves to the repo-tracked file, and then identify the current accepted `vX.Y.Z-custom.N` tag and rollback version. Never rely on memory or an old worktree.

## Current downstream contract

### 1. Separate read and write roots

Production CatDesk extends upstream workspace access with explicitly configured extra roots.

Current production policy:

```text
WORKSPACE_ROOT=/Users/hong/workspace
CATDESK_READ_ROOTS=/Users/hong:/Volumes/ExpansionDrive
CATDESK_WRITE_ROOTS=/Volumes/ExpansionDrive
```

Required semantics:

- `WORKSPACE_ROOT` remains the normal workspace boundary.
- `CATDESK_READ_ROOTS` adds explicit locations that may be read.
- `CATDESK_WRITE_ROOTS` adds explicit locations that may be written, edited, deleted, or used as move targets/sources.
- **Read permission must never imply write permission.**
- Write roots must stay readable for change tracking: the change-scope resolver takes the read boundary, so a **write-only** root would mutate without a `ChangeSession` before/after diff. Current production policy keeps every `CATDESK_WRITE_ROOTS` entry readable (`/Volumes/ExpansionDrive` appears in both lists). Adding a write-only root requires extending the change-scope resolver first, with a regression test.
- Multiple roots must use the operating system's path-list semantics.
- Do not broaden these roots to the entire home directory or an entire drive unless explicitly approved and tested.

### 2. Canonical path safety

All downstream extra-root access must preserve path-boundary security:

- Canonicalize existing candidate paths.
- For paths that do not exist yet, canonicalize the nearest existing parent before boundary validation.
- Reject traversal outside configured roots.
- Reject symlink escapes outside configured roots.
- Preserve distinct read and write boundary checks.

### 3. Canonical change tracking

Change tracking must operate on canonicalized targets so that external allowed roots, symlinks, edits, deletes, and moves produce accurate before/after tracking.

### 4. Correct command and move boundaries

The downstream behavior in `src/mcp.rs` must continue to distinguish:

- command/current-working-directory resolution that only requires read access;
- move source paths that require write permission;
- move destination paths that require write permission;
- write-boundary failures reported as write-root violations rather than generic workspace failures.

### 5. Append-only local usage ledger

Production CatDesk must expose its existing MCP token accounting as a minimal local event ledger at `~/.catdesk/usage.jsonl` for downstream usage consumers.

Required semantics:

- Keep `config.toml` usage totals as the existing cumulative state; the ledger supplements rather than replaces them.
- Append one JSONL row for each recorded MCP tool call using the stable fields `eventId`, `timestampMs`, `inputTokens`, `outputTokens`, `bucket`, and `pricingModel`.
- `pricingModel` records the ChatGPT model identity used for downstream cost estimation while CatDesk remains displayed as its own `catdesk-mcp` usage source. Update the versioned `CURRENT_USAGE_PRICING_MODEL` when the ChatGPT runtime moves to a new model; never infer the model from the accounting `bucket`.
- `eventId` must be unique per recorded event and remain the stable downstream deduplication identity even if ledger rows are moved or reordered.
- Do not duplicate derived totals such as `totalTokens` in each row.
- Production assumes the CatDesk daemon is the sole ledger writer. If a crash leaves a truncated final row, the next append must isolate that fragment with a newline before writing the next complete event.
- A ledger write failure must be logged as a warning and must not fail the MCP tool response.
- Newly created ledger files must be private to the user on Unix-like systems (`0600`).
- Do not fabricate timestamped history for usage that predates the ledger. Historical cumulative totals remain in `config.toml`.
- `usage.jsonl` is runtime state and must never be committed to this repository.

### 6. Preserve upstream release behavior

Downstream changes must never erase features introduced by newer upstream releases.

For the historical `v0.7.0` baseline, acceptance included preserving (all items remain required):

- `read` support for a `paths` array;
- the documented maximum of 32 paths per batch;
- the upstream batch read size limit;
- `poll_command` long-poll behavior and its documented wait limit;
- cursor-based incremental command output;
- draining buffered output while `hasMoreOutput=true`, even after a job reaches a terminal state;
- connector bootstrap/widget completion behavior introduced before `v0.5.0`;
- Traditional Chinese mode selection and persisted UI language preference;
- opt-in macOS Terminal.app profile flow and its persisted preference;
- macOS Chromium-family detection in standard `/Applications` and `~/Applications` bundles;
- upstream `v0.7.0` session handoff (`create_handoff`) with workspace-specific identity and ChatGPT Library recovery (native implementation; `src/handoff.rs` carries no downstream customization);
- upstream Linux sandbox SSH authentication behavior.

For the current `v0.9.0-custom.1` baseline, acceptance additionally includes preserving:

- the `widgetCornerStyle` setting end to end (config, widget payload, resource query parameter) at widget resource revision 6;
- the expanded Traditional Chinese coverage (dashboard, settings, browser selection, ngrok setup, themes, tool modes, runtime logs) while the launcher-critical English strings stay intact (`Select mode`, `Control Computer`, `Control Browser`, `Both`, `RUNNING`, `port 3200`, `Installed browsers`, `Select Browser`);
- local-time log timestamps (`local_now`, exported log filename offset);
- upstream `v0.9.0` widget surface revisions;
- upstream Linux sandbox git-metadata handling (Linux-only; no macOS runtime effect);
- upstream `v0.9.0` session handoff with `src/handoff.rs` still free of downstream customization.

Release-specific checks must be re-derived from the release notes every time upstream changes.

## Current custom source scope

The accepted `v0.7.0-custom.1` downstream implementation modifies only these upstream source files:

```text
src/change_tracking/mod.rs
src/mcp.rs
src/state.rs
src/workspace_tools.rs
```

The accepted `v0.9.0-custom.1` release needs only three of them:

```text
src/mcp.rs
src/state.rs
src/workspace_tools.rs
```

`src/change_tracking/mod.rs` is **upstream-identical** in this release: upstream `v0.8.0` absorbed the previous 7-line target-canonicalize custom with `normalize_scope_paths`, and the downstream canonicalizing resolvers keep every target canonical before it reaches `ChangeSession`. Contract §3 is locked by the downstream boundary test `external_root_targets_keep_accurate_before_after_tracking` instead of by a source delta.

This scope is descriptive, not permanent. A future upstream architecture may require fewer, different, or no downstream changes. Preserve the **behavioral contract**, not old file layouts.

## Stable macOS runtime identity and deployment contract (Phase B — PRODUCTION_ACCEPTED)

### Root cause

macOS TCC binds permissions to the binary's effective identity (filesystem path, code signature, CDHash, and Designated Requirement). Prior deployments used versioned paths such as `~/.local/share/catdesk/<version>-custom/bin/catdesk` with an **ad-hoc** signature (`Identifier=catdesk-…`, `Signature=adhoc`, `CDHash=aaa5b…`). Each new version therefore presented a **new TCC identity** (path + ad-hoc CDHash/DR) that does not inherit prior TCC grants, leaving orphaned TCC rows and requiring re-prompt.

This is confirmed by the ad-hoc production binary `0.5.0-custom.3` (`CDHash=aaa5b23ec711a827b8f981a92f7fc5c306df44ea`, `Identifier=catdesk-e6cd98f31dbf91fd`) versus any stable-signed binary.

### Deployment contract (canonical)

Every promotion MUST follow this single chain and no other path:

```text
accepted tag vX.Y.Z-custom.N
  → versioned artifact ~/.local/share/catdesk/<version>-custom/bin/catdesk (build provenance)
  → re-sign with stable signing identity com.hong.catdesk
  → physical stable runtime ~/.local/share/catdesk/runtime/bin/catdesk (launcher's only target)
  → launcher exec: spawn /Users/hong/.local/share/catdesk/runtime/bin/catdesk
  → production acceptance (ephemeral job + triple stability + MCP/Cloudflare/roots)
```

Future upgrades MUST follow GitHub-first → accepted tag → versioned artifact → stable sign/copy → stable runtime → production acceptance; never direct `git pull` on production or `runtime`.

Rules:

- `runtime/bin/catdesk` MUST be a **physical file**, never a symlink. All checks (`test -L`, `codesign -dv`, `shasum -a 256`) run against the file itself.
- Rollback is **previous accepted artifact re-signed and copied** to the **same** `runtime/bin/catdesk` path. No versioned path is ever re-introduced as a launcher target after `runtime` is adopted.
- Only after the explicit production deployment/activation approval in the required update workflow may staging create or update `~/.local/share/catdesk/runtime-next/bin/catdesk` (physical copy + sign + verify) before promotion to `runtime/bin`. Do not modify `runtime/bin` or the launcher until the staged file passes all gates and independent audit.
- `runtime/` and `runtime-next/` are production runtime state and MUST never be committed.

> **Canonical / current production (Phase B — PRODUCTION_ACCEPTED):** the launcher's **sole** target is the physical stable runtime `/Users/hong/.local/share/catdesk/runtime/bin/catdesk` (signed `Identifier=com.hong.catdesk`, `DR=identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`). Versioned artifacts `~/.local/share/catdesk/<version>-custom/bin/catdesk` remain **provenance/rollback source only** and MUST never be used as a launcher target. Historical note: before Phase B activation the running child was temporarily `/Users/hong/.local/share/catdesk/0.5.0-custom.3/bin/catdesk` (versioned path, ad-hoc `CDHash=aaa5b23ec711a827b8f981a92f7fc5c306df44ea`, `Identifier=catdesk-e6cd98f31dbf91fd`) — that state is retired and MUST NOT be read as current production.

### Stable signing identity (one-time local bootstrap)

The stable identity that makes the contract TCC-persistent is:

- **Name:** `CatDesk Local Code Signing`
- **Identifier:** `com.hong.catdesk` (passed as `codesign --identifier com.hong.catdesk`)
- **Certificate SHA-1 (non-secret):** `7F453106476B0DA6B2FEDBC4BC6F81B8C9ACA51A`
- **Certificate SHA-256 (non-secret):** `B5705686206499D677B6AF20C470D7C4C7A3E51BE1203738F2DA3F9BC8D3B043`
- **Subject (non-secret):** `CN=CatDesk Local Code Signing, OU=CatDesk Local, O=Hong Local, C=TW`
- **Expiry (non-secret):** `2028-12-04`
- **Expected DR (non-secret):** `identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`
- **TeamIdentifier:** `not set` (local self-signed)

Bootstrap is a **one-time local machine operation** that creates the Keychain certificate/keypair on that Mac. The certificate and private key are **local secrets and MUST NOT be committed to Git, stored in this repository, or logged** (no p12, no password, no raw key material — only the non-secret fingerprints/subject/expiry above are recorded). Re-creating or rotating the identity on another machine must preserve the same `Identifier` and must not be treated as an in-repo asset.

### Identity proof (cross-binary DR stability)

Two different binaries signed with this identity were independently verified to share the same DR despite different hashes:

- **A (0.5.0-custom.2 content) signed:** `SHA256=617328bd33dfe7b5d02e4e722c1d0b6db4fdeb3b01b2c096b1b81356bb5f372a`, `CDHash=8ec4dd1bfa00d343aafb80a699a3e265ed2e23f7`, `Identifier=com.hong.catdesk`, `Authority=CatDesk Local Code Signing`
- **B (0.5.0-custom.3 content) signed:** `SHA256=7e840ab9fc32f38adfa4fb187f92833c24c68fba4881410530053007d83023ac`, `CDHash=f0f90badc43c2851273dfb099d5b7a6b306236ea`, `Identifier=com.hong.catdesk`, `Authority=CatDesk Local Code Signing`
- **Both:** `Designated Requirement = identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"` and `codesign --verify --strict --verbose=4` = `valid on disk` + `satisfies its Designated Requirement`.

This proves that a stable certificate + stable identifier yields a **stable DR** that survives binary content changes, which is the TCC-persistence requirement. For each production deployment, only after explicit deployment/activation approval, the accepted release staged to `runtime-next/bin/catdesk` must exhibit the same DR and `Identifier=com.hong.catdesk`; content-specific CDHash/SHA256 values are expected to change and must be recorded per release.

### Verification gate (do not rely on `find-identity` text)

`security find-identity -v -p codesigning` may display `CSSMERR_TP_NOT_TRUSTED` for this local self-signed certificate. That warning is **informational only** and is **NOT a blocker** — empirical `codesign --verify --strict` and DR satisfaction are the gate.

After the explicit production deployment/activation approval required by the update workflow, every deploy/stage operation MUST gate on:

```bash
codesign --verify --strict --verbose=4 /Users/hong/.local/share/catdesk/runtime-next/bin/catdesk  # or runtime/bin/catdesk
codesign -dv --verbose=4 /path/to/binary  # Identifier=com.hong.catdesk, Authority=CatDesk Local Code Signing, CDHash matches expected
codesign -d -r - /path/to/binary          # designated => identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"
shasum -a 256 /path/to/binary
test ! -L /path/to/binary                  # must be physical file
```

Do not accept a binary based solely on `find-identity` listing text; the actual `codesign` verification and expected fingerprint/identifier/DR are required. Trust-policy wording variations do not invalidate the signature.

### TCC cleanup policy

Old versioned-path TCC rows (e.g., `0.5.0-custom.3` ad-hoc path) may remain as **stale cosmetic rows** until the user chooses a one-time cleanup. **Never** mutate `~/Library/Application Support/com.apple.TCC/TCC.db` via `sqlite3` or any direct DB write — that is unsupported and may corrupt TCC. Do **not** run or recommend any `tccutil reset` (global or service-scoped, e.g., `All`, `Accessibility`, `ScreenCapture`, `Automation`) for CatDesk cleanup; normal version updates MUST never perform any TCC cleanup/reset. If the user wants to clean stale entries, use **only** the supported System Settings UI (**System Settings → Privacy & Security**) to review/remove the stale versioned-path entry, then re-grant permissions interactively from the stable `runtime` path if needed. Unless the exact scope of a specific `tccutil reset <service> <client>` for that client/service has been independently verified on real hardware and is explicitly known not to reset current stable runtime permissions, it MUST NOT be recommended or executed for CatDesk cleanup. Cleanup is **not a release gate and not a production blocker**.

### TCC migration lesson (one-time bootstrap)

The first migration from the old ad-hoc/versioned-path (`~/.local/share/catdesk/<version>-custom/bin/catdesk`, ad-hoc `Identifier=catdesk-…`) to the stable signed runtime (`~/.local/share/catdesk/runtime/bin/catdesk`, `Identifier=com.hong.catdesk`, `DR=identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`) may trigger **one new macOS permission/TCC prompt** for the new stable identity. This is a **one-time bootstrap** — after the user grants it, future accepted versions MUST be promoted by **copying/signing to the same physical `runtime/bin/catdesk` path and reusing the same signing identity/Identifier/DR**. The launcher MUST never be pointed back to a versioned path after `runtime` is adopted, otherwise each version would again create a new TCC client.

### Post-activation acceptance contract (PRODUCTION_ACCEPTED)

Phase B `PRODUCTION_ACCEPTED` was granted only after all of the following passed (recorded as contract, without hard-coding PIDs):

- **Ephemeral activation job:** `launchctl bootstrap` one-shot ran **exactly once** (`runs=1`, `exit 0`), then `launchctl bootout` cleanup by the reconnected ChatGPT.
- **Process-level activation:** precise child replacement (`PPID==wrapper` + `exe==/Users/hong/.local/share/catdesk/runtime/bin/catdesk`), **30s triple stability** (wrapper PID + `runs` + stable child PID unchanged, `PPID`/`exe` still stable), and `nc -z 127.0.0.1 3200` TCP success.
- **Post-activation acceptance by reconnected ChatGPT:** MCP `catdesk_instruction` discover + `run_command`/`search`/`write`/`delete`, workspace and ExpansionDrive write/search/delete, **write-root denial** and **outside-read-root denial** (path-boundary enforcement), append-only usage ledger continuity, and **Cloudflare continuity** all PASS. Only then `PRODUCTION_ACCEPTED`.

Launcher sole target is the stable runtime; stable `codesign Identifier=com.hong.catdesk` on the same local certificate/DR; Cloudflare tunnel unchanged; read/write roots contract unchanged.

### Troubleshooting note — dedicated `read` tool schema mismatch

The dedicated `read` tool's schema `path` vs runtime `paths`/`CATDESK_READ_ROOTS` mismatch is a **pre-existing, non-blocking tool-surface issue**, not a stable-runtime or TCC regression. It is tracked separately and does not affect the Phase B `PRODUCTION_ACCEPTED` contract. Do not expand it into a new framework.

## Required update workflow for Hermes

When a new stable CatDesk release is approved for evaluation:

1. Fetch/sync this repository, confirm local `main` matches `origin/main`, and read this README plus the repo-tracked `skills/catdesk-release-update/SKILL.md` before modifying anything.
2. Confirm the local runtime skill entrypoint resolves to the repo-tracked skill, then confirm the current accepted downstream tag (`vX.Y.Z-custom.N`), clean repository state, and rollback version from tags/README — never from memory or an old worktree.
3. Fetch official upstream tags and record the new tag, commit, release notes, and relevant schema/runtime changes.
4. Start from the **new upstream stable tag**, not from a copy of old custom source files.
5. Compare the current accepted downstream behavior with the new upstream architecture.
6. Port only the **minimum custom behavior still required**. Never copy old source files wholesale over newer upstream source.
7. Preserve all applicable new upstream features and adjust the downstream implementation to the new architecture.
8. Freeze the candidate to one source commit; run formatting, upstream tests, and targeted downstream boundary/security tests on that exact revision.
9. Build a **candidate artifact** from the frozen revision for review and validation only. Record the upstream tag/commit, downstream diff, official upstream asset digest (when applicable), and candidate binary SHA-256 separately.
10. Have the independent `auditor` review that exact commit, the complete downstream diff, the candidate artifact, and measured verification results. Remediate findings on a new frozen candidate, rerun affected gates, and re-audit. Do not create an accepted downstream tag while findings remain.
11. After source tests and independent audit pass, merge the exact audited commit to downstream `main` and create the next accepted `vX.Y.Z-custom.N` tag. Verify `<tag>^{commit}` equals the audited commit; make no source edits after tagging.
12. Build the final versioned custom artifact from that accepted tag. Verify its source commit is the audited commit and record the final custom binary SHA-256 separately from the official upstream digest. A source-accepted tag is not yet `PRODUCTION_ACCEPTED`.
13. Before writing an installed versioned artifact, `runtime-next`, the stable runtime, launcher/plist, launchd state, or production config, obtain Hanqin-ge's explicit approval for production deployment/activation. Authorization to evaluate or implement the upgrade is not activation approval.
14. After approval, install under a versioned path such as `~/.local/share/catdesk/<version>-custom/bin/catdesk`; retain the previous accepted custom version for rollback.
15. Stage the stable runtime from the versioned artifact, sign and verify its stable identity, and back up the prior production binary/launcher/plist before activation. Preserve production roots/environment. **Do not rebuild or modify the Cloudflare tunnel as part of a CatDesk binary update.**
16. Activate only through the canonical stable-runtime procedure, then verify the active child and run production-surface acceptance after reconnecting ChatGPT.
17. If ExpansionDrive I/O, path security, or a required upstream feature fails, rollback immediately and report **PARTIAL/FAIL**, never PASS. Mark `PRODUCTION_ACCEPTED` only after all post-activation checks pass.

## Production activation guardrails

The 2026-08-31 `v0.5.0-custom.1` prepare/rollback incident established these mandatory controls:

- Never submit an activation helper as a `KeepAlive` launchd service; it can create an unbounded restart/browser loop even when the binary itself is healthy.
- Before activation, establish the owning launchd domain from `launchctl print`, `launchctl list`, and plist registration evidence. Do not hard-code `gui/<uid>` or `user/<uid>`; a missing service in a guessed domain is a domain/registration mismatch, not evidence of a v0.5 runtime regression.
- Keep the foreground or one-shot controller outside the CatDesk process tree: snapshot launcher/plist hashes, change only the launcher target, provide self-contained backup/rollback recipe (launcher/plist snapshots + provenance), and kickstart only CatDesk. Controller **never auto-rolls-back** — rollback is an explicit external ChatGPT decision.
- `launchctl kickstart -k` intentionally terminates the child. `SIGTERM` and Expect `spawn id ... not open` are restart evidence, not proof that the new binary crashed.
- After restart, controller verifies only process-level gates: precise replacement child (PPID==wrapper + exe==stable runtime), 30s triple stability (wrapper PID + `runs` + stable child PID unchanged, PPID/exe still stable), and `nc -z 127.0.0.1 3200`. Health/discover, root invariants and Cloudflare continuity are **post-activation acceptance** by reconnected ChatGPT, not controller gates.
- Local MCP and public ingress validation are post-activation acceptance (ChatGPT after reconnect). When Cloudflare is the active public path, a stale or legacy ngrok endpoint quota/error is only a stale probe: it is not production ingress evidence and must not drive rollback or any Cloudflare change.
- Two-phase readiness: controller preflight PASS is `READY_FOR_PROCESS_ACTIVATION` (activation may proceed); controller success (precise child + 30s triple stability + TCP PASS, or `ALREADY_ACTIVE` idempotent PASS) is `READY_FOR_POST_ACTIVATION_ACCEPTANCE`; only after reconnected ChatGPT verifies MCP/command/Cloudflare/roots all PASS is `PRODUCTION_ACCEPTED`.

## Stable runtime Phase B controller (2026-09-01 — remediation, process-level activation only)

The first Phase B attempt failed due to two root causes: (1) a `launchctl submit` job was re-dispatched and re-ran uncontrollably; (2) the controller hard-coded `/health` and `/mcp` probes, which returned 404 for the real secret-routed endpoint and was mis-evaluated as binary health failure.

Canonical Phase B controller contract (process-level activation only):

- Controller never obtains the MCP secret slug and never performs MCP discover or command execution. It does not read `~/.catdesk/config.toml` slug/token.
- `/health` and `/mcp` paths must never be hard-coded. HTTP 404 is not a controller binary-health failure; secret routes are outside controller scope.
- `launchctl submit` is forbidden for activation one-shots. It can be re-dispatched by launchd.
- When remote execution must survive the CatDesk process tree (ChatGPT→CatDesk→Hermes, where a foreground controller dies with CatDesk), use an **ephemeral `launchctl bootstrap` plist** proven by a harmless `run=1` probe: unique label `com.hong.catdesk.*`, `RunAtLoad=true`, `KeepAlive=false`, no `StartInterval`/`WatchPaths`/`StartCalendarInterval`, plist under restricted `~/.catdesk/activation/` (0700 dir, 0600 file), never under `~/Library/LaunchAgents`. After bootstrap the job must run exactly once; cleanup is `launchctl bootout <domain>/<label>` (or `bootout <domain> <plist>`) by the reconnected ChatGPT, never self-restarted by the controller.
- Single-flight uses `/usr/bin/lockf` with `lockf -k -t 0` wrapper re-exec (macOS has no `flock`). Second concurrent instance must fail immediately with busy exit (e.g. 75, `already locked`), never queue.
- Controller allows at most **one** `launchctl kickstart -k <resolved-domain>/com.hong.catdesk`, no retry loop, no auto-rollback. Any gate failure exits non-zero, preserves the private backup, and leaves the decision to the external ChatGPT.
- Controller gates are process-level only: target path is physical file (not symlink), `codesign Identifier=com.hong.catdesk` and `DR` valid (`identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`), dynamically resolved launchd domain (`gui/<uid>` or `user/<uid>`, never hard-coded), launcher/plist existence, and `nc`/`TCP` tool availability for `nc -z 127.0.0.1 3200`. It must not `curl` `/health`/`/mcp`, must not read/output any slug.
- After `--activate`, replacement verification is precise: resolve wrapper PID via `launchctl print <domain>/com.hong.catdesk`, then `ps -axo pid=,ppid=,command=` to find child where PPID==wrapper PID and first exe token precisely equals `$STABLE_RUNTIME`; plus post-restart triple 30s stability (wrapper PID + `runs` + stable child PID unchanged, PPID/exe still stable) and `nc -z 127.0.0.1 3200` success. Idempotency: if launcher already precisely stable and child already precisely stable, skip kickstart and directly do `ALREADY_ACTIVE` triple stability + TCP.
- Post-activation **acceptance** (MCP discover, command execution, Cloudflare continuity, read/write roots/boundaries, ledger) is performed by ChatGPT after reconnecting with `catdesk_instruction` (new bootstrap); failure is judged externally, and rollback is an explicit external decision that re-signs/copies the previous accepted versioned artifact to the same `runtime/bin/catdesk` path.
- Never record any secret slug, token, or tunnel credential in the repository, skill, script output, or logs.

Canonical controller artifact: `scripts/activate-stable-runtime.sh` (`--preflight` by default, `--activate` explicit). The ephemeral bootstrap procedure for remote execution is documented here and in `skills/catdesk-release-update/SKILL.md`; no daemon/service is created.

Ephemeral bootstrap for remote activation (when the controller must outlive CatDesk):

```bash
# 1. Harmless probe already proves run=1 semantics for this pattern — do not use launchctl submit.
# 2. Create restricted staging: umask 077; mkdir -p ~/.catdesk/activation (0700)
# 3. Write plist to ~/.catdesk/activation/com.hong.catdesk.activate.<timestamp>.plist (0600):
#    Label=com.hong.catdesk.activate.<timestamp>, ProgramArguments=[/path/to/scripts/activate-stable-runtime.sh --activate],
#    RunAtLoad=true, KeepAlive=false, no StartInterval/WatchPaths/StartCalendarInterval
# 4. Resolve domain dynamically: gui/<uid> if launchctl print gui/<uid>/com.hong.catdesk succeeds else user/<uid>
# 5. launchctl bootstrap <domain> <plist>  (unique label, runs exactly once)
# 6. After reconnect, ChatGPT verifies replacement + 30s stability + nc -z 127.0.0.1 3200, then MCP/Cloudflare acceptance.
# 7. Cleanup: launchctl bootout <domain>/<label> (or bootout <domain> <plist>); controller never self-bootouts or restarts.
```

## Acceptance checklist

A downstream release is not accepted merely because it compiles. Acceptance has two separate phases.

### Phase A — Source acceptance (before the accepted downstream tag)

Run these checks against the frozen candidate commit. This phase is source-only: do not write an installed artifact, `runtime-next`, the stable runtime, launcher/plist, launchd state, or production config, and do not require live production probes.

- formatting passes;
- upstream test suite passes;
- workspace read/write/edit/delete/search behavior passes;
- explicitly allowed external read behavior passes;
- explicitly allowed external write/edit/delete behavior passes;
- a read-only external root cannot be written;
- traversal and symlink escape attempts are rejected;
- change tracking remains correct for canonical/external targets;
- release-specific upstream API/schema/runtime behavior passes in isolated, non-production validation;
- all source-test temporary artifacts are removed.

Only after Phase A checks and the independent audit pass may the exact audited commit be merged and tagged as described in the required update workflow.

### Phase B — Production acceptance (after explicit deployment approval and activation)

Do not begin this phase until the source-accepted tag exists and Hanqin-ge has explicitly approved production deployment/activation. Verify the staged signature/identity gates before promotion, then verify:

- the active launchd child points to the physical stable runtime `/Users/hong/.local/share/catdesk/runtime/bin/catdesk` (the launcher's sole target; versioned artifacts are provenance/rollback source only, never a launcher target);
- CatDesk does not enter a crash loop;
- `/Volumes/ExpansionDrive` write/read/delete acceptance passes;
- Cloudflare tunnel continuity is unchanged;
- all post-activation acceptance checks in the required update workflow pass.

Do not use Phase B evidence as a prerequisite for source-tag creation, and do not mark `PRODUCTION_ACCEPTED` until every Phase B check passes.

## Provenance rules

Never confuse upstream and downstream artifact identity.

- The official upstream digest identifies the official upstream artifact.
- The custom binary digest identifies the locally built downstream production artifact.
- A successful upstream checksum does **not** prove that the official binary implements this repository's downstream contract.
- Keep the accepted downstream Git tag as the canonical source-level provenance for each production custom build.

## Never commit these items

This repository must contain source and documentation, not production runtime state.

Do **not** commit:

- API keys, access tokens, cookies, credentials, tunnel secrets, or MCP path secrets;
- `~/.catdesk/config.toml` or any real production config containing local credentials;
- production launchd plist files or launch wrappers containing environment-specific runtime data;
- Cloudflare/ngrok credentials or tunnel configuration;
- runtime logs, `~/.catdesk/usage.jsonl`, restart markers, verification output, command job state, or generated mascot/state files;
- `target/`, compiled binaries, `.dSYM` bundles, backups, temporary build output, or installed production binaries;
- secrets copied into examples, issues, commit messages, or release notes.

If deployment configuration must be documented later, use sanitized examples with placeholders only.

## Git remotes

The intended remote layout is:

```text
origin   -> private downstream repository (HCH725/CatDesk-custom)
upstream -> official public repository (Xeift/CatDesk)
```

Never force-push `main` merely to align it with upstream. Upstream changes are integrated as a reviewed downstream release update.

## Build and test

Use the upstream Rust toolchain and project instructions. Do not carry any upstream formatting-only drift downstream. Verify the downstream custom Rust files with scoped rustfmt/check commands; accepted `v0.7.0-custom.1` measured (`cargo test`: 228 passed, 0 failed; `cargo test --release`: 228 passed, 0 failed), and the accepted `v0.9.0-custom.1` measured **239 passed / 0 failed** in both profiles (`change_tracking` is upstream-identical in this release and is still checked for drift):

```bash
rustfmt --edition 2024 --check src/change_tracking/mod.rs src/mcp.rs src/state.rs src/workspace_tools.rs
cargo check
cargo test
cargo test --release
cargo build --release
sh scripts/tests/activate-controller-regression.sh
```

The activation-controller regression harness (`scripts/tests/activate-controller-regression.sh`) locks the audit-fixed controller behaviour: `--preflight` creates no activation state, changed bytes at the same stable path promote atomically with exactly one kickstart, identical bytes stay a no-op, and a missing staged artifact falls back with an explicit notice.

Accepted `v0.7.0-custom.1` keeps `src/handoff.rs` identical to upstream `v0.7.0`, and the accepted `v0.9.0-custom.1` keeps it identical to upstream `v0.9.0` (native `create_handoff`/Library recovery, no downstream customization). Release-specific and downstream boundary tests are additional requirements, not substitutes for the upstream suite.

## License and upstream attribution

This downstream repository retains the upstream MIT license and upstream copyright notice. CatDesk is originally developed by `xeift.eth` / Xeift and remains available at:

https://github.com/Xeift/CatDesk

This private repository exists only to maintain the local production customizations and their upgrade history.
