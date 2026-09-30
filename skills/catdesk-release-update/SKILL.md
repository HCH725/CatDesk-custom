# CatDesk Release Update Skill

## Purpose

Maintain `HCH725/CatDesk-custom` as a deliberately thin downstream of `Xeift/CatDesk`.

The standing source contract is:

> **upstream CatDesk + minimum controlled external read/write roots + optional thin OpenAI MCP Apps compatibility**

Do not redesign CatDesk. Do not add unrelated telemetry, monitoring, retry, or deployment concerns to Rust core.

## Authority

- `README.md` / `README.zh-TW.md` define the behavioral contract.
- This skill defines the update procedure.
- If they disagree, stop and reconcile the documentation before changing source.
- The local Hermes skill entrypoint may symlink to this file, but this repo copy is authoritative.
- Never store secrets, credentials, tunnel slugs, cookies, signing private keys, or TCC databases in this repository.

## Mandatory release order

Every future update must follow this exact order:

```text
1. official upstream stable release
2. thin downstream candidate
3. source validation
4. integrate into HCH725/CatDesk-custom
5. push private repo main + accepted custom tag
6. verify remote main + tag
7. only then build/stage local artifact
8. local production activation
9. post-activation acceptance
```

**Do not deploy a new upstream version to the Mac before the private repository has been updated, tagged, pushed, and verified.**

## Current downstream source contract

Expected standing source delta:

```text
src/mcp.rs
src/workspace_tools.rs
```

When the optional OpenAI MCP Apps compatibility layer is enabled, one additional source file is allowed:

```text
src/widget/catdesk_dashboard.html
```

That third file is limited to the minimum standards-compliant widget lifecycle/result bridge needed by OpenAI/ChatGPT entrypoints. Standard MCP and Hermes clients must continue to work without depending on this layer.

Required runtime policy:

```text
WORKSPACE_ROOT=/Users/hong/workspace
CATDESK_READ_ROOTS=/Users/hong:/Volumes/ExpansionDrive
CATDESK_WRITE_ROOTS=/Volumes/ExpansionDrive
```

Required semantics:

- workspace behavior stays upstream-compatible;
- read roots allow read/search/list only;
- write roots allow write/edit/delete/move;
- read permission never implies write permission;
- canonicalize existing targets and the nearest existing parent of missing targets;
- traversal and symlink escape outside configured roots must fail;
- `/Volumes/ExpansionDrive` must pass real I/O testing.

If a future upstream release implements the same capability natively, delete the downstream patch rather than maintaining duplicate code.

For OpenAI MCP Apps compatibility, do not vendor the `openai/mcp-extensions` repository, add a new adapter/manager framework, or alter transport/runtime behavior. Prefer namespaced metadata in existing MCP descriptors and the smallest possible bridge inside the existing widget.

## Explicit non-goals

Do not add these to CatDesk source:

- Cloudflare implementation;
- ngrok/Cloudflare switching logic;
- TokenBar integration;
- CatDesk usage ledger / custom telemetry;
- pricing model tracking;
- Hermes/Kanban integration;
- watchdog/supervisor/retry framework.

Cloudflare remains deployment transport only.

If TokenBar later needs CatDesk usage data, implement the bridge in the TokenBar private repository unless the owner explicitly approves a minimal CatDesk export hook after external options are exhausted.

## Update preflight

Before changing anything:

1. `git fetch origin`
2. `git fetch upstream --tags`
3. Confirm local `main` equals `origin/main`.
4. Confirm worktree is clean.
5. Read the current README and this skill.
6. Identify the current accepted custom tag and the new upstream stable tag.
7. Record the upstream tag and commit.
8. Review release notes and relevant source changes.

Never start from an old candidate worktree or copy old custom files wholesale.

## Build the thin candidate

1. Create a clean branch/worktree from the new upstream stable tag.
2. Reapply only the external-root contract and, if still required, the optional OpenAI MCP Apps compatibility layer.
3. Prefer adapting existing upstream functions/types instead of adding abstractions.
4. Preserve upstream MCP, state, browser, DevTools, command execution, and platform behavior unless the roots feature or the explicitly accepted OpenAI UI compatibility layer strictly requires a change.
5. Check the diff against the new upstream base.

Default expectation:

```text
git diff --name-status <upstream-tag>...HEAD
```

should normally show:

```text
M src/mcp.rs
M src/workspace_tools.rs
```

If OpenAI MCP Apps compatibility is enabled, this third source file is also permitted:

```text
M src/widget/catdesk_dashboard.html
```

Its diff must remain limited to standards-compliant widget lifecycle/result handling. Any other source file requires explicit justification in the review record.

## Source validation

Run against the exact frozen candidate revision:

```bash
cargo fmt --all -- --check
cargo check --all-targets
cargo test -- --test-threads=1
git diff --check <upstream-base> HEAD
```

Also run focused tests that prove:

- workspace read/write;
- configured local read root;
- configured external-drive read/write root;
- read-only root cannot be mutated;
- path outside read roots is denied;
- path outside write roots is denied;
- traversal is denied;
- symlink escape is denied;
- MCP tool discovery/calls still work;
- when OpenAI MCP Apps compatibility is enabled: Global/Thread entrypoint metadata is valid, widget `ui/initialize` → `ui/notifications/initialized` works, standard `ui/notifications/tool-result` consumes `params._meta`, and legacy compatibility remains intact;
- browser/DevTools source remains upstream-compatible;
- real `/Volumes/ExpansionDrive` I/O succeeds.

Do not treat macOS arbitrary shell execution as sandboxed by the roots feature. The roots contract applies to CatDesk structured file/path handling and relevant MCP path resolution.

## Independent review

A frozen candidate may be reviewed by Hermes `auditor`.

A direct invocation of the `auditor` profile is acceptable if the Kanban worker path is unavailable.

Do **not** modify Hermes CLI/runtime merely to unblock a CatDesk audit lane. If audit infrastructure itself is unavailable, report that separately; the owner decides whether existing measured evidence is sufficient to proceed.

Any source change after review invalidates that review and requires revalidation of the affected gates.

## Private-repo acceptance gate

This gate must complete **before local deployment**.

1. Integrate the validated candidate into `HCH725/CatDesk-custom`.
2. Update README/skill only for real behavior/release-state changes.
3. Confirm the private repo source diff remains intentionally thin.
4. Commit the accepted state.
5. Create the next tag:

```text
vX.Y.Z-custom.N
```

6. Push explicitly:

```bash
git push origin main
git push origin vX.Y.Z-custom.N
```

7. Fetch/read back the remote and verify:

```text
origin/main == accepted commit
remote custom tag == accepted commit
```

Only after these checks pass is the release `SOURCE_ACCEPTED` and eligible for local deployment.

## Local production deployment

Canonical production runtime:

```text
/Users/hong/.local/share/catdesk/runtime/bin/catdesk
```

Stable identity:

```text
Identifier=com.hong.catdesk
Authority=CatDesk Local Code Signing
DR=identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"
```

Deployment rules:

1. Build the release artifact from the accepted private-repo tag, not from an unpushed worktree.
2. Stage it at `~/.local/share/catdesk/runtime-next/bin/catdesk`.
3. Sign it with the existing local identity and verify `codesign --verify --strict`, Identifier, DR, physical-file status, and SHA256.
4. Run:

```text
scripts/activate-stable-runtime.sh --preflight
```

5. Activate only through the canonical one-shot controller / ephemeral launchd bootstrap path.
6. The controller may:
   - back up current production;
   - atomically promote the staged binary;
   - issue one CatDesk kickstart;
   - verify replacement child;
   - hold 30-second PID/runs/child stability;
   - verify TCP 3200.
7. The controller must not:
   - modify Cloudflare;
   - reset TCC;
   - read connector secrets;
   - add retry loops;
   - auto-rollback.

## Post-activation acceptance

After ChatGPT reconnects through the new CatDesk process, verify:

- `catdesk_instruction` responds;
- normal MCP tool calls work;
- external Mac read works;
- `/Volumes/ExpansionDrive` write → read → delete works;
- write outside configured write roots is denied;
- browser bridge responds;
- Cloudflare process/tunnel remains continuous;
- production binary signature and SHA are the expected deployed artifact.

Only then mark the release `PRODUCTION_ACCEPTED`.

## Rollback

The activation controller creates a timestamped pre-activation backup under:

```text
~/.catdesk/activation/backups/
```

If a production-critical boundary fails:

1. stop further changes;
2. restore the previous accepted binary to the same stable runtime path;
3. preserve the stable signing identity;
4. restart only CatDesk;
5. re-run post-activation acceptance.

Do not alter Cloudflare or reset TCC as part of normal rollback.

## Current accepted release

As of 2026-09-27:

- upstream: `v0.9.5` / `f4f4bcc6a14b87f00d17f102f3006dfd96c0b341`
- downstream: `v0.9.5-custom.2`
- deployed thin candidate provenance: `9679f5b08825b39cb5587d5363ea0faf5f530224`
- production SHA256: `8c98eb715a9366ce5c3cc3725de609dbd27575916bca33ec05c7f861586612fe`
- source delta: `src/mcp.rs`, `src/workspace_tools.rs` only
- usage ledger/telemetry customization: intentionally removed
- Cloudflare: unchanged, deployment layer only

The 2026-09-27 cutover happened before this private-repo reconciliation by explicit owner direction. Treat that ordering as historical only. **All future upgrades are private-repo-first.**
