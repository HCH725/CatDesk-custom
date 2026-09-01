---
name: catdesk-release-update
description: Use when updating CatDesk downstream extra-roots releases.
---

# CatDesk downstream release update

CatDesk is not a pure upstream installation. The production artifact is an upstream Xeift/CatDesk stable release plus the smallest necessary local downstream extra-roots patch.

## Authority model (read first)

- This repo-tracked skill is the **canonical operational procedure** for Hermes `default` profile (how to perform an update).
- The repository README (`README.md`, or `README.zh-TW.md`) is the **canonical behavioral contract** (what must remain true) and wins on any conflict.
- If this skill and the README disagree, **stop the upgrade**, reconcile this skill with the README, and only then continue.
- The local runtime entrypoint `~/.hermes/skills/software-development/catdesk-release-update/SKILL.md` is only a Hermes symlink entrypoint and must resolve to this repo-tracked file (symlink). It is not a separate source of truth. Runtime relinking is deliberate and separately gated; do not bypass it.
- Never store secrets, tokens, slugs, cookies, or credentials in this skill or anywhere in the repository.

## Source-of-truth hierarchy (GitHub-first)

Production CatDesk must never track `main` directly. Each level is reviewed before it feeds the next:

1. **Upstream stable tag** — the official `Xeift/CatDesk` stable release (tag + commit + release notes + official artifact) is the top source of truth for release behavior.
2. **Downstream private repository** — reviewed `main` and the current accepted `vX.Y.Z-custom.N` tag in `HCH725/CatDesk-custom` are the source of truth for downstream policy. Nothing is accepted by merge or tag until it has passed acceptance and independent audit.
3. **Local production deployment** — the **physical stable runtime** `/Users/hong/.local/share/catdesk/runtime/bin/catdesk` (launcher's sole canonical target post-migration, Phase B) built from the versioned artifact `~/.local/share/catdesk/<version>-custom/bin/catdesk` (accepted-tag provenance / rollback source) is what actually runs in the canonical state. **Transitional current state (Phase A — pre-activation, not canonical):** the actually running production child is still temporarily `/Users/hong/.local/share/catdesk/0.5.0-custom.3/bin/catdesk` (versioned path, ad-hoc) spawned by the launcher — this is migration-before-Phase-B evidence only and MUST NOT be read as the canonical contract. Versioned artifacts remain provenance/rollback source only, never a launcher target after `runtime` is adopted.

Update flow (canonical): **accepted tag `vX.Y.Z-custom.N` → versioned artifact `~/.local/share/catdesk/<version>-custom/bin/catdesk` (provenance/rollback source) → sign/copy with stable identity `com.hong.catdesk` → physical stable runtime `~/.local/share/catdesk/runtime/bin/catdesk` → launcher**. Production is built from the accepted tag via this chain, never by following `main` or any old worktree.

## Stable macOS runtime identity and deployment contract (Phase A — ROOT_CAUSE_CONFIRMED)

### Root cause

macOS TCC binds to effective identity (path + signature + CDHash + DR). Versioned `~/.local/share/catdesk/<version>-custom/bin/catdesk` with ad-hoc signature (`Identifier=catdesk-…`, `Signature=adhoc`, `CDHash=aaa5b…`) creates a **new TCC identity per version** that does not inherit prior grants. The production ad-hoc `0.5.0-custom.3` (`CDHash=aaa5b23ec711a827b8f981a92f7fc5c306df44ea`, `Identifier=catdesk-e6cd98f31dbf91fd`) versus any stable-signed binary confirms this.

### Canonical deployment chain

```text
accepted tag vX.Y.Z-custom.N
  → versioned artifact ~/.local/share/catdesk/<version>-custom/bin/catdesk (build provenance)
  → re-sign with stable signing identity com.hong.catdesk
  → physical stable runtime ~/.local/share/catdesk/runtime/bin/catdesk (launcher's ONLY target)
  → launcher spawn /Users/hong/.local/share/catdesk/runtime/bin/catdesk
```

- `runtime/bin/catdesk` MUST be a **physical file**, never a symlink (`test ! -L`).
- Rollback = re-sign and copy the **previous accepted versioned artifact** to the **same** `runtime/bin/catdesk` path. Never re-point the launcher to a versioned path after `runtime` is adopted.
- Staging validation path is `~/.local/share/catdesk/runtime-next/bin/catdesk` (physical copy → sign → verify). Do not touch `runtime/bin` or the launcher until the staged file passes all gates and independent audit.
- `runtime/` and `runtime-next/` are runtime state and MUST never be committed.

### Stable signing identity (one-time local bootstrap — local secret)

- **Name:** `CatDesk Local Code Signing` — **Identifier:** `com.hong.catdesk` (`codesign --identifier com.hong.catdesk`)
- **SHA-1 (non-secret):** `7F453106476B0DA6B2FEDBC4BC6F81B8C9ACA51A`
- **SHA-256 (non-secret):** `B5705686206499D677B6AF20C470D7C4C7A3E51BE1203738F2DA3F9BC8D3B043`
- **Subject (non-secret):** `CN=CatDesk Local Code Signing, OU=CatDesk Local, O=Hong Local, C=TW` — **Expiry (non-secret):** `2028-12-04`
- **Expected DR (non-secret):** `identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"` — **TeamIdentifier:** `not set`

Bootstrap is a **one-time local machine operation** that creates the Keychain certificate/keypair. Certificate and private key are **local secrets and MUST NOT be committed to Git, stored in this skill, or logged** (no p12, no password, no raw key material). Only the non-secret fingerprints/subject/expiry above are recorded.

### Identity proof

Two different contents signed with this identity prove DR stability despite different hashes:

- **A (0.5.0-custom.2 content) signed:** `SHA256=617328bd33dfe7b5d02e4e722c1d0b6db4fdeb3b01b2c096b1b81356bb5f372a`, `CDHash=8ec4dd1bfa00d343aafb80a699a3e265ed2e23f7`, `Identifier=com.hong.catdesk`, `Authority=CatDesk Local Code Signing`
- **B (0.5.0-custom.3 content) signed:** `SHA256=7e840ab9fc32f38adfa4fb187f92833c24c68fba4881410530053007d83023ac`, `CDHash=f0f90badc43c2851273dfb099d5b7a6b306236ea`, `Identifier=com.hong.catdesk`, `Authority=CatDesk Local Code Signing`
- **Both:** `Designated Requirement = identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"` and `codesign --verify --strict --verbose=4` = `valid on disk` + `satisfies its Designated Requirement`.

Staging from current accepted `0.5.0-custom.3` to `runtime-next/bin/catdesk` must show the same DR (`CDHash=f0f90badc43c2851273dfb099d5b7a6b306236ea` for that content).

### Verification gate (`CSSMERR_TP_NOT_TRUSTED` is NOT a blocker)

`security find-identity -v -p codesigning` may show `CSSMERR_TP_NOT_TRUSTED` for this local self-signed cert. This is **informational only** — the gate is the actual codesign verification. Every deploy/stage MUST run and pass:

```bash
codesign --verify --strict --verbose=4 /Users/hong/.local/share/catdesk/runtime-next/bin/catdesk  # or runtime/bin/catdesk
codesign -dv --verbose=4 /path/to/binary  # Identifier=com.hong.catdesk, Authority=CatDesk Local Code Signing
codesign -d -r - /path/to/binary          # designated => identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"
shasum -a 256 /path/to/binary
test ! -L /path/to/binary                  # must be physical file
```

Do not gate on `find-identity` display text alone; the expected fingerprint/identifier/DR via `codesign` are mandatory. Trust-policy wording variations do not invalidate the signature.

### TCC cleanup policy

TCC cleanup stays **deferred** until stable `runtime/bin/catdesk` is activated and accepted. **Never** mutate `~/Library/Application Support/com.apple.TCC/TCC.db` via `sqlite3` or any direct DB write (unsupported — may corrupt TCC).

When one-time cleanup is warranted post-activation, use only supported paths: **System Settings → Privacy & Security** or `tccutil reset` (e.g., `tccutil reset All com.hong.catdesk` or scoped `Accessibility`/`ScreenCapture`/`Automation` resets), then re-grant permissions interactively from the stable `runtime` path. Leave versioned-path TCC rows orphaned until then.

## Preflight before any update

Never rely on memory or stale worktrees. Every update must start from fresh repository state, in order:

1. Fetch/sync the downstream `origin` repo and confirm local `main` matches `origin/main`; record clean-worktree state.
2. Read the README (canonical behavioral contract) and this repo-tracked skill (canonical operational procedure) from the synced repository.
3. Confirm the local runtime entrypoint `~/.hermes/skills/software-development/catdesk-release-update/SKILL.md` resolves to this repo-tracked file (symlink target check).
4. Identify the current accepted downstream tag `vX.Y.Z-custom.N` from `git tag`/README, and the rollback version from the previous accepted tag or the versioned install path. Do not hardcode a v0.x worktree or a fixed accepted tag as the future baseline.
5. If the README and this skill conflict, stop and reconcile before any further step.

## Required release workflow

1. Fetch the stable tag and record repository, tag, commit, remote, and clean-worktree state.
2. Read release notes and compare API/schema/runtime changes before porting anything.
3. Preserve the previous accepted downstream patch as an auditable diff; derive/rebase only the minimal extra-roots policy into a clean worktree for the new tag. The new baseline is the new upstream stable tag, not any old custom worktree.
4. Do not copy old source files wholesale over newer source. Preserve upstream release features and adapt to the new architecture.
5. Keep read and write boundaries separate: read is allowed only under `WORKSPACE_ROOT` plus configured `CATDESK_READ_ROOTS`; write/delete/edit/move is allowed only under `WORKSPACE_ROOT` plus configured `CATDESK_WRITE_ROOTS`. Read permission must never imply write permission.
6. Use OS path-list semantics for `CATDESK_READ_ROOTS` and `CATDESK_WRITE_ROOTS`. Canonicalize existing paths and parents of missing paths so traversal and symlink escapes cannot leave configured roots. Do not expand monitoring to an entire home or drive without explicit provenance and tests.
7. Run targeted boundary tests and the relevant upstream suite before building: workspace read/write, external read/write, read-only external root, traversal/symlink escape, change tracking, the append-only `~/.catdesk/usage.jsonl` ledger contract, and release-specific schema behavior.
8. Run formatting and tests, then release-build an arm64 binary. Record upstream tag/commit, downstream diff, official asset digest for provenance, and custom binary SHA256 for production identity. The custom digest must not be reported as the official digest.
9. Install under a clearly versioned custom path, for example `/Users/hong/.local/share/catdesk/<version>-custom/bin/catdesk`. Keep the previously accepted custom version until the new one is stable. Record the versioned artifact SHA256 as build provenance; the versioned artifact is the **source** for the stable runtime, not the launcher target after `runtime` is adopted.
10. Stage the stable runtime: physical copy the versioned artifact to `~/.local/share/catdesk/runtime-next/bin/catdesk`, sign it with `CatDesk Local Code Signing` as `com.hong.catdesk` (`codesign --force --sign "CatDesk Local Code Signing" --identifier com.hong.catdesk`), then gate on `codesign --verify --strict --verbose=4`, `codesign -dv`, `codesign -d -r -` (expected DR `identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`), `shasum -a 256`, and `test ! -L`. Do not promote to `~/.local/share/catdesk/runtime/bin/catdesk` or change the launcher until this staged file passes and is audited. `CSSMERR_TP_NOT_TRUSTED` in `find-identity` output is informational only and must not block, but actual `codesign --verify --strict` plus expected fingerprint/identifier/DR must pass.
11. Timestamp-backup the previous production binary, launcher, plist, and a rollback recipe. Change only the launcher spawn binary path; preserve plist roots and environment. Restart only `com.hong.catdesk`; never modify the Cloudflare tunnel for a CatDesk update. After `runtime` is adopted, the launcher MUST point only to `/Users/hong/.local/share/catdesk/runtime/bin/catdesk` and rollback MUST be previous accepted artifact re-signed/copied to that same path.
12. Verify the active launchd child path, running state and lack of crash-loop, Cloudflare tunnel continuity, all root environment invariants, workspace CRUD/search, ExpansionDrive write/read/delete, safe command execution, and release-specific tools/schema/runtime behavior. Clean every test artifact.
13. If ExpansionDrive I/O or a security boundary fails, rollback immediately to the previous accepted custom version and report PARTIAL, not PASS.

## Release-specific smoke checklist

Derive this dynamically from each release's notes; never treat a previous release's checklist as the future baseline. Historical exemplars (v0.4.2/v0.4.3): `read` accepts a `paths` array with a maximum of 32 items; `poll_command` retains long-poll behavior with its documented wait limit; connector bootstrap/widget completion behavior is not overwritten by the downstream port. Confirm each item against the new release's notes before applying it.

## Historical pitfalls (recorded from the v0.4.3 update)

- A successful official asset checksum does not prove the asset meets local custom requirements.
- Environment variables being present does not prove the binary implements their semantics.
- `diff` exit code 1 means expected differences when comparing changed source; do not treat that as deploy failure.
- Restarting the daemon invalidates external command job handles; that is expected and does not by itself mean the upgrade failed.
- The ExpansionDrive gate is production-critical, not an optional convenience test.
- The local token ledger is production runtime state, not repository content. Preserve the append-only `eventId` / `timestampMs` / `inputTokens` / `outputTokens` / `bucket` contract across upgrades; keep `eventId` stable and unique per event, isolate a truncated crash-tail before the next append, and never backfill fabricated timestamps.
- Acceptance must be based on active production-surface readbacks, not only source tests or child-agent claims.

## Production activation incident guardrails (2026-08-31)

- Never place a one-shot activation helper in a `KeepAlive` launchd job; it can create an unbounded restart/browser loop even when the binary itself is healthy.
- Before activation, establish the owning launchd domain from `launchctl print`, `launchctl list`, and plist registration evidence. Do not hard-code `gui/<uid>` or `user/<uid>`; a missing service in a guessed domain is a domain/registration mismatch, not evidence of a v0.5 runtime regression.
- Keep activation helpers foreground/one-shot and outside the CatDesk process tree: snapshot launcher/plist hashes, change only the launcher target, provide self-contained rollback, and kickstart only CatDesk.
- `kickstart -k` intentionally terminates the current child; `SIGTERM`/exit 143 and Expect `spawn id ... not open` are restart evidence, not proof that the new binary crashed. After restart, verify the replacement child path, health/discover, crash-loop stability, root invariants, and Cloudflare continuity.
- Treat local MCP and the configured public ingress/provider as separate gates. A local HTTP 200 does not clear a public endpoint failure; record the public status and sanitized provider error. When Cloudflare is the active public path, a stale or legacy ngrok endpoint quota/error is only a stale probe: it is not production ingress evidence and must not drive rollback or any Cloudflare change.
- Only report `READY_FOR_ACTIVATION` after the one-shot helper is absent, the intended child is verified, the crash-loop gate is stable, local and active-public MCP gates pass, and rollback provenance has been read back.

## Stable runtime Phase B controller (2026-09-01 — remediation, process-level activation only)

First Phase B failed for two root causes: (1) `launchctl submit` was re-dispatched and re-ran; (2) the controller hard-coded `/health`/`/mcp`, which 404s on the real secret route and was mis-evaluated as binary failure.

Canonical controller contract — **process-level activation only**, no MCP/secret knowledge:

- Controller never obtains the secret slug and never does MCP discover/command. It does not read `~/.catdesk/config.toml` slug/token and never outputs any slug.
- Never hard-code `/health` or `/mcp`. HTTP 404 is not a controller binary-health failure.
- **Forbidden:** `launchctl submit` for activation one-shots. It can be re-dispatched by launchd (run>1 incident).
- When the control chain is ChatGPT→CatDesk→Hermes and a foreground controller would die with CatDesk, use an **ephemeral `launchctl bootstrap` plist** whose `run=1` semantics were proven by a harmless probe: unique label `com.hong.catdesk.activate.<timestamp>`, `RunAtLoad=true`, `KeepAlive=false`, no `StartInterval`/`WatchPaths`/`StartCalendarInterval`, plist under restricted `~/.catdesk/activation/` (0700 dir, 0600 file), never under `~/Library/LaunchAgents`. After bootstrap the job runs exactly once; cleanup is `launchctl bootout <domain>/<label>` (or `bootout <domain> <plist>`) by the reconnected ChatGPT — the controller never self-restarts or self-bootouts.
- Single-flight is `/usr/bin/lockf` with `lockf -k -t 0` wrapper re-exec (macOS has no `flock`). File `~/.catdesk/activation/activate.lock` (0600). Second concurrent instance must fail immediately busy (75 `already locked`), never queue. The script `scripts/activate-stable-runtime.sh` already implements this re-exec pattern.
- At most **one** `launchctl kickstart -k <resolved-domain>/com.hong.catdesk` per invocation, no retry loop, no auto-rollback, never touch Cloudflare/TCC. Any gate failure exits non-zero, preserves the private backup (`~/.catdesk/activation/backups/<ts>-<pid>/`), and leaves the decision to external ChatGPT.
- Preflight (`--preflight`, the default when `--activate` is not given) is read-only and checks: stable runtime is physical file (`test ! -L`), `codesign --verify --strict`, `Identifier=com.hong.catdesk`, `DR=identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`, dynamically resolved domain (`gui/<uid>` or `user/<uid>`), launcher/plist existence, `nc` availability. No `curl` to `/health`/`/mcp`, no secret read.
- Activate (`--activate`) re-does preflight under lock, saves private backup of launcher/plist metadata, changes **only** the launcher `spawn` target to `STABLE_RUNTIME` (default `/Users/hong/.local/share/catdesk/runtime/bin/catdesk`), issues one kickstart, then verifies replacement via macOS-native `ps aux` path (`.../runtime/bin/catdesk`), takes post-restart `PID`/`runs` baseline (`launchctl print`), holds 30s and re-checks `PID`+`runs` unchanged, then `nc -z 127.0.0.1 3200`. No HTTP probe.
- Post-activation **acceptance** (MCP discover, command execution, Cloudflare continuity, read/write roots/boundaries, ledger) is done by ChatGPT after reconnecting via `catdesk_instruction` on the new bootstrap; only if that fails does external ChatGPT decide rollback (re-sign/copy previous accepted versioned artifact to the same `runtime/bin/catdesk` path).

Canonical artifact: `scripts/activate-stable-runtime.sh` — minimal, only `sh`/`codesign`/`launchctl`/`nc`/`ps`/`shasum`, no Homebrew `flock`/`jq`, no `launchctl submit`, no daemon.

Ephemeral bootstrap for remote activation (Hermes would die with CatDesk, so ChatGPT launches via Hermes out-of-tree):

```bash
# ChatGPT side (via Hermes bootstrap, not inside CatDesk tree):
# 0. Preflight locally: scripts/activate-stable-runtime.sh --preflight (must PASS, no secret output)
# 1. Verify run=1 probe semantics already proven for launchctl bootstrap RunAtLoad=true KeepAlive=false
umask 077; mkdir -p ~/.catdesk/activation; chmod 700 ~/.catdesk/activation
# 2. Write ephemeral plist ~/.catdesk/activation/com.hong.catdesk.activate.<timestamp>.plist (0600):
#    Label=com.hong.catdesk.activate.<timestamp>
#    ProgramArguments=[/Users/hong/workspace/CatDesk-custom/scripts/activate-stable-runtime.sh --activate]
#    RunAtLoad=true, KeepAlive=false, no StartInterval/WatchPaths/StartCalendarInterval
# 3. Resolve domain: UID=$(id -u); if launchctl print gui/$UID/com.hong.catdesk >/dev/null 2>&1; then D=gui/$UID; else D=user/$UID; fi
# 4. launchctl bootstrap $D ~/.catdesk/activation/com.hong.catdesk.activate.<timestamp>.plist  # runs once
# 5. After CatDesk restarts, ChatGPT reconnects with new catdesk_instruction, checks:
#    ps aux | grep -F /Users/hong/.local/share/catdesk/runtime/bin/catdesk
#    launchctl print $D/com.hong.catdesk (PID+runs 30s stability)
#    nc -z 127.0.0.1 3200
#    then MCP discover / command / Cloudflare / roots acceptance
# 6. Cleanup (by reconnected ChatGPT, not controller): launchctl bootout $D/com.hong.catdesk.activate.<timestamp>
#    (or launchctl bootout $D ~/.catdesk/activation/com.hong.catdesk.activate.<timestamp>.plist)
```