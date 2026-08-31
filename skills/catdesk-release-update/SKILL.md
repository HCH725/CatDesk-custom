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
3. **Local production deployment** — the versioned custom binary installed from the accepted tag, e.g. `/Users/hong/.local/share/catdesk/<version>-custom/bin/catdesk`, is what actually runs.

Update flow: **upstream stable tag → downstream reviewed main/accepted tag → local production deployment**. Production is built and deployed from the accepted tag, never by following `main` or any old worktree.

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
7. Run targeted boundary tests and the relevant upstream suite before building: workspace read/write, external read/write, read-only external root, traversal/symlink escape, change tracking, and release-specific schema behavior.
8. Run formatting and tests, then release-build an arm64 binary. Record upstream tag/commit, downstream diff, official asset digest for provenance, and custom binary SHA256 for production identity. The custom digest must not be reported as the official digest.
9. Install under a clearly versioned custom path, for example `/Users/hong/.local/share/catdesk/<version>-custom/bin/catdesk`. Keep the previously accepted custom version until the new one is stable.
10. Timestamp-backup the previous production binary, launcher, plist, and a rollback recipe. Change only the launcher spawn binary path; preserve plist roots and environment. Restart only `com.hong.catdesk`; never modify the Cloudflare tunnel for a CatDesk update.
11. Verify the active launchd child path, running state and lack of crash-loop, Cloudflare tunnel continuity, all root environment invariants, workspace CRUD/search, ExpansionDrive write/read/delete, safe command execution, and release-specific tools/schema/runtime behavior. Clean every test artifact.
12. If ExpansionDrive I/O or a security boundary fails, rollback immediately to the previous accepted custom version and report PARTIAL, not PASS.

## Release-specific smoke checklist

Derive this dynamically from each release's notes; never treat a previous release's checklist as the future baseline. Historical exemplars (v0.4.2/v0.4.3): `read` accepts a `paths` array with a maximum of 32 items; `poll_command` retains long-poll behavior with its documented wait limit; connector bootstrap/widget completion behavior is not overwritten by the downstream port. Confirm each item against the new release's notes before applying it.

## Historical pitfalls (recorded from the v0.4.3 update)

- A successful official asset checksum does not prove the asset meets local custom requirements.
- Environment variables being present does not prove the binary implements their semantics.
- `diff` exit code 1 means expected differences when comparing changed source; do not treat that as deploy failure.
- Restarting the daemon invalidates external command job handles; that is expected and does not by itself mean the upgrade failed.
- The ExpansionDrive gate is production-critical, not an optional convenience test.
- Acceptance must be based on active production-surface readbacks, not only source tests or child-agent claims.

## Production activation incident guardrails (2026-08-31)

- Never place a one-shot activation helper in a `KeepAlive` launchd job; it can create an unbounded restart/browser loop even when the binary itself is healthy.
- Before activation, establish the owning launchd domain from `launchctl print`, `launchctl list`, and plist registration evidence. Do not hard-code `gui/<uid>` or `user/<uid>`; a missing service in a guessed domain is a domain/registration mismatch, not evidence of a v0.5 runtime regression.
- Keep activation helpers foreground/one-shot and outside the CatDesk process tree: snapshot launcher/plist hashes, change only the launcher target, provide self-contained rollback, and kickstart only CatDesk.
- `kickstart -k` intentionally terminates the current child; `SIGTERM`/exit 143 and Expect `spawn id ... not open` are restart evidence, not proof that the new binary crashed. After restart, verify the replacement child path, health/discover, crash-loop stability, root invariants, and Cloudflare continuity.
- Treat local MCP and the configured public ingress/provider as separate gates. A local HTTP 200 does not clear a public endpoint failure; record the public status and sanitized provider error. When Cloudflare is the active public path, a stale or legacy ngrok endpoint quota/error is only a stale probe: it is not production ingress evidence and must not drive rollback or any Cloudflare change.
- Only report `READY_FOR_ACTIVATION` after the one-shot helper is absent, the intended child is verified, the crash-loop gate is stable, local and active-public MCP gates pass, and rollback provenance has been read back.