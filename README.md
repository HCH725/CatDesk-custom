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
- **Current upstream baseline:** `v0.5.0`
- **Current upstream commit:** `0e958123c25284cd9ead1ba171ed1c3c8f58d7c5`
- **Downstream release naming:** `vX.Y.Z-custom.N`
- **Production source of truth:** this private repository after a downstream release has passed acceptance and audit

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
- Append one JSONL row for each recorded MCP tool call using the stable fields `eventId`, `timestampMs`, `inputTokens`, `outputTokens`, and `bucket`.
- `eventId` must be unique per recorded event and remain the stable downstream deduplication identity even if ledger rows are moved or reordered.
- Do not duplicate derived totals such as `totalTokens` in each row.
- Production assumes the CatDesk daemon is the sole ledger writer. If a crash leaves a truncated final row, the next append must isolate that fragment with a newline before writing the next complete event.
- A ledger write failure must be logged as a warning and must not fail the MCP tool response.
- Newly created ledger files must be private to the user on Unix-like systems (`0600`).
- Do not fabricate timestamped history for usage that predates the ledger. Historical cumulative totals remain in `config.toml`.
- `usage.jsonl` is runtime state and must never be committed to this repository.

### 6. Preserve upstream release behavior

Downstream changes must never erase features introduced by newer upstream releases.

For the current `v0.5.0` baseline, acceptance includes preserving:

- `read` support for a `paths` array;
- the documented maximum of 32 paths per batch;
- the upstream batch read size limit;
- `poll_command` long-poll behavior and its documented wait limit;
- cursor-based incremental command output;
- draining buffered output while `hasMoreOutput=true`, even after a job reaches a terminal state;
- connector bootstrap/widget completion behavior introduced before `v0.5.0`;
- Traditional Chinese mode selection and persisted UI language preference;
- opt-in macOS Terminal.app profile flow and its persisted preference;
- macOS Chromium-family detection in standard `/Applications` and `~/Applications` bundles.

Release-specific checks must be re-derived from the release notes every time upstream changes.

## Current custom source scope

The `v0.5.0` downstream implementation currently modifies only these upstream source files:

```text
src/change_tracking/mod.rs
src/mcp.rs
src/state.rs
src/workspace_tools.rs
```

This scope is descriptive, not permanent. A future upstream architecture may require fewer, different, or no downstream changes. Preserve the **behavioral contract**, not old file layouts.

## Required update workflow for Hermes

When a new stable CatDesk release is approved for evaluation:

1. Fetch/sync this repository, confirm local `main` matches `origin/main`, and read this README plus the repo-tracked `skills/catdesk-release-update/SKILL.md` before modifying anything.
2. Confirm the local runtime skill entrypoint resolves to the repo-tracked skill, then confirm the current accepted downstream tag (`vX.Y.Z-custom.N`), clean repository state, and rollback version from tags/README — never from memory or an old worktree.
3. Fetch official upstream tags and record the new tag, commit, release notes, and relevant schema/runtime changes.
4. Start from the **new upstream stable tag**, not from a copy of old custom source files.
5. Compare the current accepted downstream behavior with the new upstream architecture.
6. Port only the **minimum custom behavior still required**. Never copy old source files wholesale over newer upstream source.
7. Preserve all applicable new upstream features and adjust the downstream implementation to the new architecture.
8. Run formatting, upstream tests, and targeted downstream boundary/security tests before building.
9. Build the custom production artifact and record separately:
   - upstream tag and commit;
   - downstream diff;
   - upstream official artifact digest, when applicable;
   - custom binary SHA-256.
10. Install the custom binary under a versioned path such as `~/.local/share/catdesk/<version>-custom/bin/catdesk`.
11. Keep the previously accepted custom version available for rollback. Back up the launcher/plist before deployment.
12. Change only what the CatDesk binary update requires. Preserve production roots/environment. **Do not rebuild or modify the Cloudflare tunnel as part of a CatDesk binary update.**
13. Restart only the CatDesk service, then run production-surface acceptance tests.
14. If ExpansionDrive I/O, path security, or a required upstream feature fails, rollback immediately and report **PARTIAL/FAIL**, never PASS.
15. Run an independent `auditor` review before declaring the new downstream release accepted.
16. Only after acceptance and audit, merge the result into `main` and create the next `vX.Y.Z-custom.N` tag.

## Production activation guardrails

The 2026-08-31 `v0.5.0-custom.1` prepare/rollback incident established these mandatory controls:

- Never submit an activation helper as a `KeepAlive` launchd service; it can create an unbounded restart/browser loop even when the binary itself is healthy.
- Before activation, establish the owning launchd domain from `launchctl print`, `launchctl list`, and plist registration evidence. Do not hard-code `gui/<uid>` or `user/<uid>`; a missing service in a guessed domain is a domain/registration mismatch, not evidence of a v0.5 runtime regression.
- Keep the foreground or one-shot controller outside the CatDesk process tree: snapshot launcher/plist hashes, change only the launcher target, provide self-contained rollback, and kickstart only CatDesk.
- `launchctl kickstart -k` intentionally terminates the child. `SIGTERM` and Expect `spawn id ... not open` are restart evidence, not proof that the new binary crashed.
- After restart, verify the replacement child path, health/discover, crash-loop stability, root invariants, and Cloudflare continuity.
- Validate local MCP health/protocol calls separately from the configured public MCP endpoint. When Cloudflare is the active public path, a stale or legacy ngrok endpoint quota/error is only a stale probe: it is not production ingress evidence and must not drive rollback or any Cloudflare change.
- Declare `READY_FOR_ACTIVATION` only after the one-shot controller is absent, the intended child is verified, the crash-loop gate is stable, local and active-public MCP gates pass, and rollback provenance has been read back.

## Acceptance checklist

A downstream release is not accepted merely because it compiles.

At minimum, verify:

- formatting passes;
- upstream test suite passes;
- workspace read/write/edit/delete/search behavior passes;
- explicitly allowed external read behavior passes;
- explicitly allowed external write/edit/delete behavior passes;
- a read-only external root cannot be written;
- traversal and symlink escape attempts are rejected;
- change tracking remains correct for canonical/external targets;
- release-specific upstream API/schema/runtime behavior passes;
- the active launchd child points to the intended versioned custom binary;
- CatDesk does not enter a crash loop;
- `/Volumes/ExpansionDrive` write/read/delete acceptance passes;
- Cloudflare tunnel continuity is unchanged;
- all temporary test artifacts are removed.

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

Use the upstream Rust toolchain and project instructions. Clean upstream `v0.5.0` has a pre-existing rustfmt drift in `src/browser.rs`, so do not carry that formatting-only change downstream. Verify the three downstream custom Rust files with scoped rustfmt/check commands, and retain the upstream test result (`cargo test`: 215 passed, 0 failed):

```bash
rustfmt --edition 2024 --check src/change_tracking/mod.rs src/mcp.rs src/workspace_tools.rs
cargo check
cargo test
```

The clean upstream `v0.5.0` full-tree `cargo fmt --check` is expected to fail only on that pre-existing `src/browser.rs` formatting drift; it is not part of the downstream custom scope. Release-specific and downstream boundary tests are additional requirements, not substitutes for the upstream suite.

## License and upstream attribution

This downstream repository retains the upstream MIT license and upstream copyright notice. CatDesk is originally developed by `xeift.eth` / Xeift and remains available at:

https://github.com/Xeift/CatDesk

This private repository exists only to maintain the local production customizations and their upgrade history.
