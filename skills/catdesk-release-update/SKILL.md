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
2. **Downstream private repository** — reviewed `main` and the current source-accepted `vX.Y.Z-custom.N` tag in `HCH725/CatDesk-custom` are the source of truth for downstream policy. A merge/tag requires source acceptance (frozen-commit tests plus independent audit); `PRODUCTION_ACCEPTED` remains a separate post-activation state.
3. **Local production deployment** — the **physical stable runtime** `/Users/hong/.local/share/catdesk/runtime/bin/catdesk` (**canonical / current production**, Phase B — PRODUCTION_ACCEPTED, launcher's sole target) built from the versioned artifact `~/.local/share/catdesk/<version>-custom/bin/catdesk` (accepted-tag provenance / rollback source) is what actually runs. Versioned artifacts remain provenance/rollback source only and MUST never be used as a launcher target. Historical note: before Phase B activation the running child was temporarily `/Users/hong/.local/share/catdesk/0.5.0-custom.3/bin/catdesk` (versioned path, ad-hoc) — that state is retired.

Update flow (canonical): **accepted tag `vX.Y.Z-custom.N` → versioned artifact `~/.local/share/catdesk/<version>-custom/bin/catdesk` (provenance/rollback source) → sign/copy with stable identity `com.hong.catdesk` → physical stable runtime `~/.local/share/catdesk/runtime/bin/catdesk` → launcher → production acceptance**. Production is built from the accepted tag via this chain, never by following `main`, any old worktree, or direct `git pull` on production.

## Stable macOS runtime identity and deployment contract (Phase B — PRODUCTION_ACCEPTED)

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
- Only after the explicit production deployment/activation approval in Required release workflow step 12 may staging create or update `~/.local/share/catdesk/runtime-next/bin/catdesk` (physical copy → sign → verify). Do not touch `runtime/bin` or the launcher until the staged file passes all gates and independent audit.
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

Do not stage or rewrite the currently accepted downstream artifact as an update preflight. `runtime-next` is production runtime state. Only after the explicit production deployment/activation approval in Required release workflow step 12, stage the final versioned artifact built from the audited source-accepted tag at `~/.local/share/catdesk/runtime-next/bin/catdesk`, then apply the stable signing identity and require the `Identifier` and DR above. The `0.5.0-custom.3` CDHash above is historical identity evidence only; never treat it as the current content hash or a future baseline.

### Verification gate (`CSSMERR_TP_NOT_TRUSTED` is NOT a blocker)

`security find-identity -v -p codesigning` may show `CSSMERR_TP_NOT_TRUSTED` for this local self-signed cert. This is **informational only** — the gate is the actual codesign verification. After the explicit deployment/activation approval, every staged/deployed binary MUST run and pass:

```bash
codesign --verify --strict --verbose=4 /Users/hong/.local/share/catdesk/runtime-next/bin/catdesk  # or runtime/bin/catdesk
codesign -dv --verbose=4 /path/to/binary  # Identifier=com.hong.catdesk, Authority=CatDesk Local Code Signing
codesign -d -r - /path/to/binary          # designated => identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"
shasum -a 256 /path/to/binary
test ! -L /path/to/binary                  # must be physical file
```

Do not gate on `find-identity` display text alone; the expected fingerprint/identifier/DR via `codesign` are mandatory. Trust-policy wording variations do not invalidate the signature.

### TCC cleanup policy

Old versioned-path TCC rows (e.g., `0.5.0-custom.3` ad-hoc path) may remain as **stale cosmetic rows** until the user chooses a one-time cleanup. **Never** mutate `~/Library/Application Support/com.apple.TCC/TCC.db` via `sqlite3` or any direct DB write (unsupported — may corrupt TCC). Do **not** run or recommend any `tccutil reset` (global or service-scoped, e.g., `All`, `Accessibility`, `ScreenCapture`, `Automation`) for CatDesk cleanup; normal version updates MUST never perform any TCC cleanup/reset. If the user wants to clean stale entries, use **only** the supported System Settings UI (**System Settings → Privacy & Security**) to review/remove the stale versioned-path entry, then re-grant permissions interactively from the stable `runtime` path if needed. Unless the exact scope of a specific `tccutil reset <service> <client>` for that client/service has been independently verified on real hardware and is explicitly known not to reset current stable runtime permissions, it MUST NOT be recommended or executed for CatDesk cleanup. Cleanup is **not a release gate and not a production blocker**.

### TCC migration lesson (one-time bootstrap)

The first migration from the old ad-hoc/versioned-path (`~/.local/share/catdesk/<version>-custom/bin/catdesk`, ad-hoc) to the stable signed runtime (`~/.local/share/catdesk/runtime/bin/catdesk`, `Identifier=com.hong.catdesk`, `DR=identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`) may trigger **one new macOS permission/TCC prompt** for the new stable identity. This is a **one-time bootstrap** — after the user grants it, future accepted versions MUST be promoted by **copying/signing to the same physical `runtime/bin/catdesk` path and reusing the same signing identity/Identifier/DR**. The launcher MUST never be pointed back to a versioned path after `runtime` is adopted, otherwise each version would again create a new TCC client.

### Post-activation acceptance contract (PRODUCTION_ACCEPTED)

Phase B `PRODUCTION_ACCEPTED` was granted only after (without hard-coding PIDs): ephemeral `launchctl bootstrap` one-shot `runs=1`/`exit 0`; precise child replacement (`PPID==wrapper` + `exe==stable runtime`), 30s triple stability (wrapper PID + `runs` + stable child PID unchanged) + `nc -z 127.0.0.1 3200`; and reconnected ChatGPT acceptance — MCP `catdesk_instruction` discover + `catdesk_command`/`search`/`write`/`delete`, ExpansionDrive read/write, **write-root denial** and **outside-read-root denial**, and **Cloudflare continuity** all PASS. Launcher sole target is the stable runtime; same local certificate/DR; Cloudflare unchanged; roots contract unchanged. Future upgrades MUST follow GitHub-first → accepted tag → versioned artifact → stable sign/copy → stable runtime → production acceptance, never direct `git pull` on production.

### Troubleshooting note — dedicated `read` tool schema mismatch

The dedicated `read` tool's schema `path` vs runtime `paths`/`CATDESK_READ_ROOTS` mismatch is a **pre-existing, non-blocking tool-surface issue**, not a stable-runtime or TCC regression. Tracked separately; do not expand into a new framework.

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
3. Preserve the previous accepted downstream patch as an auditable diff; port the minimal extra-roots policy into a clean worktree for the new tag using 3-way merge: `git merge-file` the upstream versioned files against the previous custom versions. The new baseline is the new upstream stable tag, not any old custom worktree. Expected conflict locations for CatDesk are `src/change_tracking/mod.rs` and `src/state.rs` (struct field additions). Resolve conflicts by reading both sides, not by accepting one side blindly.
4. Do not copy old source files wholesale over newer source. Preserve upstream release features and adapt to the new architecture.
5. Keep read and write boundaries separate: read is allowed only under `WORKSPACE_ROOT` plus configured `CATDESK_READ_ROOTS`; write/delete/edit/move is allowed only under `WORKSPACE_ROOT` plus configured `CATDESK_WRITE_ROOTS`. Read permission must never imply write permission.
6. Use OS path-list semantics for `CATDESK_READ_ROOTS` and `CATDESK_WRITE_ROOTS`. Canonicalize existing paths and parents of missing paths so traversal and symlink escapes cannot leave configured roots. Do not expand monitoring to an entire home or drive without explicit provenance and tests.
7. Freeze one candidate source commit and run targeted boundary tests plus the relevant upstream suite against that exact revision: workspace read/write, external read/write, read-only external root, traversal/symlink escape, change tracking, append-only `~/.catdesk/usage.jsonl` ledger behavior, and release-specific schema behavior.
8. Run formatting and the full test suite, then build a **candidate** arm64 artifact from the frozen commit for review only. Record the upstream tag/commit, downstream diff, official upstream asset digest when applicable, and candidate binary SHA256 separately; a candidate artifact is not yet production output.
9. Obtain an independent `auditor` review of that exact commit, full diff, candidate artifact, and measured checks. Remediate any findings on a new frozen candidate, rerun affected gates, and re-audit. Do not merge or tag while findings remain.
10. After source tests and audit pass, merge the exact audited commit to downstream `main` and create the next source-accepted `vX.Y.Z-custom.N` tag. Verify `<tag>^{commit}` equals the audited commit and make no source edits after tagging.
11. Build the final versioned artifact from that accepted tag; verify its source commit equals the audited commit and record the final custom binary SHA256 separately from the official upstream digest. A source-accepted tag is not yet `PRODUCTION_ACCEPTED`.
12. Before writing an installed versioned artifact, `runtime-next`, the stable runtime, launcher/plist, launchd state, or production config, obtain Hanqin-ge's explicit approval for production deployment/activation. Approval to evaluate or implement the upgrade is not activation approval.
13. After approval, install under a clearly versioned custom path, for example `/Users/hong/.local/share/catdesk/<version>-custom/bin/catdesk`, and keep the previous accepted artifact available for rollback.
14. Stage the stable runtime: physical copy the versioned artifact to `~/.local/share/catdesk/runtime-next/bin/catdesk`, sign it with `CatDesk Local Code Signing` as `com.hong.catdesk` (`codesign --force --sign "CatDesk Local Code Signing" --identifier com.hong.catdesk`), then gate on `codesign --verify --strict --verbose=4`, `codesign -dv`, `codesign -d -r -` (expected DR `identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`), `shasum -a 256`, and `test ! -L`. Do not promote to `~/.local/share/catdesk/runtime/bin/catdesk` or change the launcher until this staged file passes all gates and is audited.
15. Timestamp-backup the previous production binary, launcher, plist, and a rollback recipe. Use **atomic rename** (`mv`) — not in-place `cp` — when replacing the live binary; preserve roots/environment and never modify the Cloudflare tunnel.
16. Activate only through the canonical controller. After reconnecting ChatGPT, verify the active launchd child, stable runtime, workspace CRUD/search, ExpansionDrive I/O, read/write-root denials, ledger continuity, Cloudflare continuity, and release-specific behavior; mark `PRODUCTION_ACCEPTED` only after all post-activation gates pass.
17. If ExpansionDrive I/O or a security boundary fails, rollback to the previous accepted artifact and report PARTIAL, not PASS.

## Release-specific smoke checklist

### Launcher expect-script compatibility (standing requirement)

Every version upgrade must verify that the launcher's expect patterns still match the new TUI rendering. The launcher (`catdesk-launch.tcl`) depends on specific English-mode string matches to drive the interactive setup. If upstream translates these screens or changes the key mapping, the launcher silently times out and enters a restart loop.

**Standing verification before every activation:**
1. Grep the new source for each critical string: `press any key to skip`, `CatDesk Connector Refresh Required`, `Select mode`, `Control Computer`, `Control Browser`, `Both`, `RUNNING`, `port 3200`, `Installed browsers`, `Select Browser`.
2. Verify the mode-select key mapping: `KeyCode::Char('1')` → Computer, `'2'` → Browser, `'3'` → Both (launcher sends `3`).
3. Check whether upstream added `if zh` / zh-TW rendering to screens the launcher depends on (mode selection, browser selection). If so, verify the production UI language config to ensure English rendering is used (check for `ui_language` key in `~/.catdesk/config.toml` absent = default English; **never read the file for secrets** — grep only the language key line).
4. If any critical string is missing or remapped, the launcher MUST be updated before activation.

Pitfall: upstream v0.8.0 expanded zh-TW to mode selection and browser selection screens. If the production language were zh-TW, the launcher's `expect -re "Select mode"` would NOT match Chinese text. The launcher only works because the config defaults to English.

Derive this dynamically from each release's notes; never treat a previous release's checklist as the future baseline. Historical exemplars (v0.4.2/v0.4.3): `read` accepts a `paths` array with a maximum of 32 items; `poll_command` retains long-poll behavior with its documented wait limit; connector bootstrap/widget completion behavior is not overwritten by the downstream port. Confirm each item against the new release's notes before applying it.

## Historical pitfalls (recorded from the v0.4.3 update)

- When upstream absorbs a downstream custom code path (e.g., upstream `normalize_scope_paths` replacing a manual canonicalize loop), delete the redundant custom code entirely — do not keep both. Add a downstream contract test that locks the boundary behavior, and ensure the file matches upstream exactly. Keeping dead custom code alongside its upstream equivalent creates merge noise and false diff signals in every future upgrade.
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
- Keep activation helpers foreground/one-shot and outside the CatDesk process tree: snapshot launcher/plist hashes, change only the launcher target, provide self-contained backup/rollback recipe (launcher/plist snapshots + provenance), and kickstart only CatDesk. Controller **never auto-rolls-back** — rollback is an explicit external ChatGPT decision.
- `kickstart -k` intentionally terminates the current child; `SIGTERM`/exit 143 and Expect `spawn id ... not open` are restart evidence, not proof that the new binary crashed. After restart, controller verifies only process-level gates: precise replacement child (PPID==wrapper + exe==stable runtime), 30s triple stability (wrapper PID + `runs` + stable child PID unchanged, PPID/exe still stable), and `nc -z 127.0.0.1 3200`. Health/discover, root invariants and Cloudflare continuity are **post-activation acceptance** by reconnected ChatGPT, not controller gates.
- Treat local MCP and the configured public ingress/provider as post-activation acceptance (ChatGPT after reconnect). When Cloudflare is the active public path, a stale or legacy ngrok endpoint quota/error is only a stale probe: it is not production ingress evidence and must not drive rollback or any Cloudflare change.
- Two-phase readiness: controller preflight PASS is `READY_FOR_PROCESS_ACTIVATION` (activation may proceed); controller success (precise child + 30s triple stability + TCP PASS, or `ALREADY_ACTIVE` idempotent PASS) is `READY_FOR_POST_ACTIVATION_ACCEPTANCE`; only after reconnected ChatGPT verifies MCP/command/Cloudflare/roots all PASS is `PRODUCTION_ACCEPTED`.

## Stable runtime Phase B controller (2026-09-01 — remediation, process-level activation only)

First Phase B failed for two root causes: (1) `launchctl submit` was re-dispatched and re-ran; (2) the controller hard-coded `/health`/`/mcp`, which 404s on the real secret route and was mis-evaluated as binary failure.

Canonical controller contract — **process-level activation only**, no MCP/secret knowledge:

- Controller never obtains the secret slug and never does MCP discover/command. It does not read `~/.catdesk/config.toml` slug/token and never outputs any slug.
- Never hard-code `/health` or `/mcp`. HTTP 404 is not a controller binary-health failure.
- **Forbidden:** `launchctl submit` for activation one-shots. It can be re-dispatched by launchd (run>1 incident).
- When the control chain is ChatGPT→CatDesk→Hermes and a foreground controller would die with CatDesk, use an **ephemeral `launchctl bootstrap` plist** whose `run=1` semantics were proven by a harmless probe: unique label `com.hong.catdesk.activate.<timestamp>`, `RunAtLoad=true`, `KeepAlive=false`, no `StartInterval`/`WatchPaths`/`StartCalendarInterval`, plist under restricted `~/.catdesk/activation/` (0700 dir, 0600 file), never under `~/Library/LaunchAgents`. After bootstrap the job runs exactly once; cleanup is `launchctl bootout <domain>/<label>` (or `bootout <domain> <plist>`) by the reconnected ChatGPT — the controller never self-restarts or self-bootouts.
- Single-flight is `/usr/bin/lockf` with `lockf -k -t 0` wrapper re-exec (macOS has no `flock`). File `~/.catdesk/activation/activate.lock` (0600). Second concurrent instance must fail immediately busy (75 `already locked`), never queue. The script `scripts/activate-stable-runtime.sh` already implements this re-exec pattern.
- At most **one** `launchctl kickstart -k <resolved-domain>/com.hong.catdesk` per invocation, no retry loop, no auto-rollback, never touch Cloudflare/TCC. Any gate failure exits non-zero, preserves the private backup (`~/.catdesk/activation/backups/<ts>-<pid>/`), and leaves the decision to external ChatGPT.
- Preflight (`--preflight`, the default when `--activate` is not given) is read-only and checks: stable runtime is physical file (`test ! -L`), `codesign --verify --strict`, `Identifier=com.hong.catdesk`, `DR=identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"`, dynamically resolved domain (`gui/<uid>` or `user/<uid>`), launcher/plist existence, `nc` availability. No `curl` to `/health`/`/mcp`, no secret read, and it must not create, touch or truncate any activation state: `--preflight` takes no lock, only `--activate` does.
- Activate (`--activate`) re-does preflight under lock, saves private backup of launcher/plist metadata, changes **only** the launcher `spawn` target via atomic same-filesystem replace (temp in launcher dir + verify + chmod + `mv`, exactly one `spawn` line, FAIL otherwise), issues one kickstart, then verifies replacement precisely: resolve wrapper PID via `launchctl print <domain>/com.hong.catdesk`, `ps -axo pid=,ppid=,command=` to find child where PPID==wrapper PID and first exe token precisely equals `STABLE_RUNTIME`, takes post-restart wrapper `PID`/`runs`/child PID triple baseline, holds 30s and re-checks triple unchanged (PPID/exe still stable), then `nc -z 127.0.0.1 3200`. No HTTP probe. Idempotency: if launcher already precisely stable and child already precisely stable **and the staged content is identical**, skip kickstart and directly do `ALREADY_ACTIVE` triple 30s + TCP. **Content identity (version upgrades):** `--activate` compares the staged artifact digest (default `~/.local/share/catdesk/runtime-next/bin/catdesk`; override with `--staged PATH` or `CATDESK_STAGED_RUNTIME`) against the stable runtime digest. Different bytes trigger the atomic content promotion: staged identity gates → private backup (launcher, plist, current runtime binary, and a `ROLLBACK.txt` recipe) → atomic `mv` of a digest-verified temp copy over `runtime/bin/catdesk` (never an in-place `cp` over a running binary) → post-swap digest/codesign/DR gates → exactly one `launchctl kickstart -k` → replacement verification that additionally requires the child PID to change → 30s triple stability → TCP. If no staged artifact exists, the run falls back to path-only idempotency and prints an explicit notice.
- Post-activation **acceptance** (MCP discover, command execution, Cloudflare continuity, read/write roots/boundaries, ledger) is done by ChatGPT after reconnecting via `catdesk_instruction` on the new bootstrap; only if that fails does external ChatGPT decide rollback (re-sign/copy previous accepted versioned artifact to the same `runtime/bin/catdesk` path).

Canonical artifact: `scripts/activate-stable-runtime.sh` — minimal, only `sh`/`codesign`/`launchctl`/`nc`/`ps`/`shasum`, no Homebrew `flock`/`jq`, no `launchctl submit`, no daemon. Regression coverage: `scripts/tests/activate-controller-regression.sh` (T1 preflight purity, T2 changed-bytes atomic promotion with exactly one kickstart, T3 identical-bytes no-op, T4 missing-staged notice) — run it before any activation.

Ephemeral bootstrap for remote activation (Hermes would die with CatDesk, so ChatGPT launches via Hermes out-of-tree):

```bash
# ChatGPT side (via Hermes bootstrap, not inside CatDesk tree):
# 0. Preflight locally: scripts/activate-stable-runtime.sh --preflight (must PASS, no secret output)
# 1. Verify run=1 probe semantics already proven for launchctl bootstrap RunAtLoad=true KeepAlive=false
umask 077; mkdir -p ~/.catdesk/activation; chmod 700 ~/.catdesk/activation
# 2. Write ephemeral plist ~/.catdesk/activation/com.hong.catdesk.activate.<timestamp>.plist (0600):
#    Label=com.hong.catdesk.activate.<timestamp>
#    ProgramArguments=[<path to the checked-out catdesk-release-update repo>/scripts/activate-stable-runtime.sh --activate]
#      Use the script from the checkout that tracks this skill (e.g. `$(git rev-parse --show-toplevel)/scripts/activate-stable-runtime.sh`
#      from that repo), never a stale sibling checkout. The staged artifact path can be injected with `--staged PATH`.
#    RunAtLoad=true, KeepAlive=false, no StartInterval/WatchPaths/StartCalendarInterval
# 3. Resolve domain: UID=$(id -u); if launchctl print gui/$UID/com.hong.catdesk >/dev/null 2>&1; then D=gui/$UID; else D=user/$UID; fi
# 4. launchctl bootstrap $D ~/.catdesk/activation/com.hong.catdesk.activate.<timestamp>.plist  # runs once
# 5. After CatDesk restarts, ChatGPT reconnects with new catdesk_instruction, checks:
#    ps -axo pid=,ppid=,command= | awk -v wpid=$(launchctl print $D/com.hong.catdesk | awk '/pid =/ {print $3}') -v target=/Users/hong/.local/share/catdesk/runtime/bin/catdesk 'ppid==wpid && $3==target'
#    launchctl print $D/com.hong.catdesk (wrapper PID+runs+child PID triple 30s stability)
#    nc -z 127.0.0.1 3200
#    then MCP discover / command / Cloudflare / roots acceptance (PRODUCTION_ACCEPTED)
# 6. Cleanup (by reconnected ChatGPT, not controller): launchctl bootout $D/com.hong.catdesk.activate.<timestamp>
#    (or launchctl bootout $D ~/.catdesk/activation/com.hong.catdesk.activate.<timestamp>.plist)
```