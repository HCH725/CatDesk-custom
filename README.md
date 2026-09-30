# CatDesk Custom

[English](README.md) | [繁體中文](README.zh-TW.md)

Private downstream repository for the CatDesk instance used on Hanqin-ge's Mac.

The design goal is intentionally narrow:

> **official Xeift/CatDesk upstream + the minimum external-filesystem patch + an optional thin OpenAI MCP Apps compatibility layer**

Cloudflare, launchd, code signing, and production activation are deployment concerns. They are not CatDesk source customizations.

## Current accepted state

- **Upstream:** https://github.com/Xeift/CatDesk
- **Private downstream:** https://github.com/HCH725/CatDesk-custom
- **Accepted upstream release:** `v0.9.5`
- **Accepted upstream commit:** `f4f4bcc6a14b87f00d17f102f3006dfd96c0b341`
- **Accepted downstream release:** `v0.9.5-custom.2`
- **Current production runtime:** `/Users/hong/.local/share/catdesk/runtime/bin/catdesk`
- **Current production SHA256:** `8c98eb715a9366ce5c3cc3725de609dbd27575916bca33ec05c7f861586612fe`
- **Stable signing identifier:** `com.hong.catdesk`
- **Public ingress:** Cloudflare Tunnel, managed outside CatDesk source
- **Current accepted production source delta vs upstream:** exactly two Rust files:
  - `src/mcp.rs`
  - `src/workspace_tools.rs`
- **OpenAI MCP Apps compatibility candidate:** may additionally touch `src/widget/catdesk_dashboard.html`, but only for the minimal standards-compliant UI lifecycle/result bridge required by ChatGPT entrypoints.

All other CatDesk source files should remain upstream-identical unless a future upstream change makes a different minimal implementation strictly necessary. The OpenAI compatibility layer must stay additive: standard MCP behavior, Hermes clients, transport, and filesystem semantics must not depend on it.

## Why this repository exists

Upstream CatDesk normally constrains file tools to its workspace. This deployment also needs controlled access to selected local and external-drive paths.

Current policy:

```text
WORKSPACE_ROOT=/Users/hong/workspace
CATDESK_READ_ROOTS=/Users/hong:/Volumes/ExpansionDrive
CATDESK_WRITE_ROOTS=/Volumes/ExpansionDrive
```

Required behavior:

- workspace access continues to work normally;
- configured read roots may be read/search/listed;
- configured write roots may be written/edited/deleted/moved;
- read permission never implies write permission;
- canonicalization must block traversal and symlink escapes;
- paths outside configured roots must be rejected;
- `/Volumes/ExpansionDrive` must remain usable for real read/write operations.

The external-filesystem contract remains the primary standing CatDesk customization. A second, optional customization is permitted only for thin OpenAI MCP Apps compatibility: namespaced OpenAI entrypoint metadata plus the minimum widget lifecycle/result bridge needed by ChatGPT. Do not vendor `openai/mcp-extensions`, add a parallel framework, or make standard MCP/Hermes depend on this layer.

## Explicitly not part of CatDesk custom source

The following are separate concerns and must not be added back into CatDesk core merely for convenience:

- Cloudflare Tunnel;
- launchd service management;
- activation/restart orchestration;
- TokenBar integration;
- CatDesk usage ledger / telemetry;
- pricing-model tracking;
- Hermes/Kanban integration.

If CatDesk usage data is needed by TokenBar in the future, implement that integration in the TokenBar private repository or through an external read-only bridge. Do not reintroduce a CatDesk `state.rs` usage ledger unless there is no viable external interface and the owner explicitly approves it.

## Source-of-truth order

The release order is mandatory:

```text
Xeift/CatDesk upstream stable release
        ↓
HCH725/CatDesk-custom private repo
  reviewed main + accepted custom tag
        ↓
local release build from that accepted tag
        ↓
runtime-next signing / verification
        ↓
stable local production runtime
        ↓
post-activation acceptance
```

**Never deploy a new upstream version directly to the Mac before the corresponding private-repo commit/tag has been pushed and verified.**

The private repository is the downstream source of truth. The local Mac is a deployment target, not a source repository.

## Ownership and operating model

1. Hanqin-ge decides whether an upstream CatDesk release should be adopted.
2. ChatGPT reviews the release and keeps the scope minimal.
3. Hermes `default` may implement the update.
4. Hermes `auditor` may independently review the frozen candidate; a direct `auditor` profile invocation is acceptable.
5. Do not modify or expand Hermes runtime merely to make a CatDesk audit lane work.
6. ChatGPT verifies repository state, deployment, and post-activation behavior.

The README is the behavioral contract.
`skills/catdesk-release-update/SKILL.md` is the operational procedure.

## Required update workflow

When Xeift/CatDesk publishes a new stable release:

1. Fetch `origin` and `upstream`. Confirm local `main == origin/main` and the worktree is clean.
2. Read the new upstream release notes and inspect API/schema/runtime changes.
3. Create a clean candidate from the new upstream stable tag/commit.
4. Port only the minimum extra-roots behavior still required, plus the optional OpenAI MCP Apps compatibility layer if it is still needed. Do not copy old custom source wholesale.
5. Prefer deleting downstream code when upstream has absorbed equivalent behavior.
6. Verify the downstream source diff. The default source delta is `src/mcp.rs` and `src/workspace_tools.rs`. `src/widget/catdesk_dashboard.html` is additionally allowed only when the OpenAI MCP Apps compatibility layer is active and its review record proves the change is limited to standards-compliant UI lifecycle/result handling. Any other source file requires an explicit justification.
7. Run source validation:
   - `cargo fmt --all -- --check`
   - `cargo check --all-targets`
   - full Rust tests
   - focused read/write-root tests
   - traversal/symlink escape tests
   - real `/Volumes/ExpansionDrive` read/write test
   - `git diff --check`
8. Integrate the accepted candidate into this private repository. Update README/skill only when behavior or release state changed.
9. Create the next `vX.Y.Z-custom.N` tag and push **both `main` and the tag to `origin`**.
10. Read back `origin/main` and the remote tag. They must resolve to the intended accepted commit.
11. **Only after step 10** may local production deployment begin.
12. Build the local release artifact from the accepted private-repo tag.
13. Stage/sign it as `com.hong.catdesk` under `runtime-next`, run the read-only activation preflight, then use the canonical one-shot activation controller.
14. Reconnect from ChatGPT and run post-activation acceptance:
    - MCP tool calls;
    - external local read;
    - ExpansionDrive write/read/delete;
    - write-root denial;
    - browser bridge;
    - Cloudflare continuity.
15. Keep the controller-created pre-activation backup as the rollback source. If a production-critical boundary fails, roll back rather than adding new infrastructure.

## Stable macOS runtime

Canonical production path:

```text
/Users/hong/.local/share/catdesk/runtime/bin/catdesk
```

It must remain a physical file and retain the stable local signing identity:

```text
Identifier=com.hong.catdesk
Authority=CatDesk Local Code Signing
Designated Requirement:
identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"
```

The launcher continues to point only to the stable runtime path.

The canonical activation helper is:

```text
scripts/activate-stable-runtime.sh
```

Its job is deliberately limited to process-level activation: backup, atomic promotion, one kickstart, child replacement verification, 30-second stability, and TCP 3200. It must not mutate Cloudflare or TCC and must not contain MCP secrets.

## Cloudflare

Cloudflare is the current public ingress and is intentionally independent of CatDesk source.

```text
ChatGPT
   ↓
Cloudflare Tunnel
   ↓
localhost:3200
   ↓
CatDesk
```

An upstream CatDesk update must not replace Cloudflare with ngrok, edit the tunnel configuration, or treat Cloudflare as a downstream Rust patch.

## 2026-09-27 thin-custom reconciliation

The production thin candidate was frozen as:

```text
9679f5b08825b39cb5587d5363ea0faf5f530224
```

Relative to upstream `v0.9.5`, its source delta is:

```text
src/mcp.rs             |  41 +++---
src/workspace_tools.rs | 364 +++++++++++++++++++++++++++++++++++++++++++++++-
2 files changed, 381 insertions(+), 24 deletions(-)
```

Measured validation before activation:

- `cargo fmt --check`: PASS
- `cargo check --all-targets`: PASS
- Rust tests: **250/250 PASS**
- real ExpansionDrive focused test: PASS
- release build: PASS

Production activation on 2026-09-27:

- atomic runtime replacement: PASS
- stable code-signing / DR: PASS
- replacement child observed: PASS
- 30-second triple stability: PASS
- TCP 3200: PASS
- ChatGPT MCP reconnect: PASS
- external local read: PASS
- ExpansionDrive write/read/delete: PASS
- write outside configured write roots: correctly denied
- browser bridge: PASS
- Cloudflare continuity: PASS
- rollback backup: `~/.catdesk/activation/backups/20260927-170554-67118`

This release was reconciled into the private repository immediately after the user-approved production cutover. That ordering is a **one-time historical exception**. Future releases must follow the private-repo-first order defined above.

## Repository hygiene

- Do not commit runtime binaries, `runtime-next`, activation backups, credentials, tunnel secrets, cookies, TCC databases, or local signing private keys.
- Do not maintain parallel implementations of behavior that upstream already provides.
- Do not add monitoring, retry, watchdog, compatibility, or telemetry frameworks to CatDesk unless the core connector itself requires them.
- Keep deployment scripts separate from Rust source customization.
- Do not force-push `main` merely to align with upstream; integrate reviewed upstream releases as normal downstream commits/tags.

## Upstream attribution and license

This downstream repository is based on Xeift/CatDesk and retains the upstream license and attribution. Upstream project:

https://github.com/Xeift/CatDesk
