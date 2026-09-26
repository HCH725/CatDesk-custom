#!/bin/sh
# CatDesk stable-runtime Phase B controller — process-level activation only.
# - No secret handling, no MCP discover, no /health or /mcp hardcoding.
# - Single kickstart, no retry, no auto-rollback, no Cloudflare/TCC mutation.
# - Uses /usr/bin/lockf for single-flight (macOS has no flock).
# - Default mode is --preflight (safe, read-only). --activate is explicit.
set -eu

STABLE_RUNTIME_DEFAULT="/Users/hong/.local/share/catdesk/runtime/bin/catdesk"
STABLE_RUNTIME="${CATDESK_STABLE_RUNTIME:-$STABLE_RUNTIME_DEFAULT}"
STAGED_RUNTIME_DEFAULT="/Users/hong/.local/share/catdesk/runtime-next/bin/catdesk"
STAGED_RUNTIME="${CATDESK_STAGED_RUNTIME:-$STAGED_RUNTIME_DEFAULT}"
LAUNCHER="${CATDESK_LAUNCHER:-/Users/hong/.local/share/catdesk/catdesk-launch.tcl}"
PLIST="${CATDESK_PLIST:-/Users/hong/Library/LaunchAgents/com.hong.catdesk.plist}"
LOCK_DIR="${CATDESK_ACTIVATION_DIR:-$HOME/.catdesk/activation}"
LOCK_FILE="$LOCK_DIR/activate.lock"
EXPECTED_DR='identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"'
EXPECTED_ID="com.hong.catdesk"

# --- arg parsing (side-effect free; --preflight must stay read-only) ---
MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --preflight) MODE="preflight"; shift ;;
    --activate) MODE="activate"; shift ;;
    --staged)
      if [ $# -lt 2 ]; then echo "ERR: --staged requires path" >&2; exit 2; fi
      STAGED_RUNTIME="$2"; shift 2 ;;
    --staged=*) STAGED_RUNTIME="${1#--staged=}"; shift ;;
    --stable-runtime)
      if [ $# -lt 2 ]; then echo "ERR: --stable-runtime requires path" >&2; exit 2; fi
      STABLE_RUNTIME="$2"; shift 2 ;;
    --stable-runtime=*) STABLE_RUNTIME="${1#--stable-runtime=}"; shift ;;
    -h|--help)
      cat <<HELP
Usage: $0 [--preflight] [--activate] [--staged PATH] [--stable-runtime PATH]
  No flags      -> --preflight only (safe default, no mutation, no activation state)
  --preflight   -> read-only gates, no production mutation and no lock/state writes
  --activate    -> lock, preflight, backup, single kickstart, 30s stability + TCP check
  --staged PATH -> staged artifact whose content identity is compared with the stable
                   runtime; identical content is a genuine no-op, different content is
                   promoted atomically (rename) with exactly one kickstart.
                   Default: $STAGED_RUNTIME_DEFAULT
  --stable-runtime PATH -> override canonical stable runtime (default: $STABLE_RUNTIME_DEFAULT)
HELP
      exit 0 ;;
    *) echo "ERR: unknown arg $1" >&2; exit 2 ;;
  esac
done
if [ -z "$MODE" ]; then MODE="preflight"; fi

# --- single-flight via lockf re-exec (macOS lockf, not flock) ---
# Only the mutating path takes the lock: --preflight must not create, touch or
# truncate any activation state (it is a read-only gate).
# Second concurrent activation fails immediately (busy, nonzero) not queue.
if [ "$MODE" = "activate" ] && [ -z "${CATDESK_ACTIVATE_LOCKED:-}" ]; then
  umask 077
  mkdir -p "$LOCK_DIR"
  chmod 700 "$LOCK_DIR" 2>/dev/null || true
  : > "$LOCK_FILE" 2>/dev/null || touch "$LOCK_FILE"
  chmod 600 "$LOCK_FILE" 2>/dev/null || true
  # Args were already parsed (and consumed), so re-exec with the resolved values.
  # -k keeps lock file (0700/0600); -t 0 = fail immediately if busy.
  CATDESK_ACTIVATE_LOCKED=1 exec /usr/bin/lockf -k -t 0 "$LOCK_FILE" "$0" \
    --activate --stable-runtime "$STABLE_RUNTIME" --staged "$STAGED_RUNTIME"
fi

resolve_domain() {
  _uid=$(id -u)
  if launchctl print "gui/$_uid/com.hong.catdesk" >/dev/null 2>&1; then
    echo "gui/$_uid"
    return 0
  fi
  if launchctl print "user/$_uid/com.hong.catdesk" >/dev/null 2>&1; then
    echo "user/$_uid"
    return 0
  fi
  echo "ERR: cannot resolve launchd domain for com.hong.catdesk (tried gui/$_uid user/$_uid)" >&2
  return 1
}

get_wrapper_pid() {
  _domain="$1"
  launchctl print "$_domain/com.hong.catdesk" 2>&1 | awk '/^[[:space:]]*pid =/ {print $3}'
}

get_wrapper_runs() {
  _domain="$1"
  launchctl print "$_domain/com.hong.catdesk" 2>&1 | awk '/^[[:space:]]*runs =/ {print $3}'
}

# Precise child PID: PPID==wrapper PID AND first executable token == STABLE_RUNTIME
# Uses macOS ps -axo pid=,ppid=,command= to avoid grep substring matching controller itself.
get_stable_child_pid() {
  _wpid="$1"
  _target="$2"
  ps -axo pid=,ppid=,command= 2>&1 | awk -v wpid="$_wpid" -v target="$_target" '
    {
      pid=$1; ppid=$2; $1=""; $2=""; sub(/^ +/, "", $0);
      n=split($0, a, /[[:space:]]+/); exe=a[1];
      if (ppid==wpid && exe==target) { print pid; found=1; exit 0 }
    }
    END { if (!found) exit 1 }
  '
}

is_launcher_stable() {
  _target="$1"
  _launcher="$2"
  if [ ! -f "$_launcher" ]; then return 1; fi
  _total=$(grep -cE '^[[:space:]]*spawn[[:space:]]+.*catdesk' "$_launcher" 2>/dev/null || true)
  if [ "$_total" != "1" ]; then return 1; fi
  _matched=$(awk -v target="$_target" '
    /^[[:space:]]*spawn[[:space:]]+/ {
      line=$0; sub(/^[[:space:]]*spawn[[:space:]]+/, "", line);
      n=split(line, a, /[[:space:]]+/); exe=a[1];
      if (exe==target) c++;
    }
    END { if (c==1) print "yes" }
  ' "$_launcher")
  [ "$_matched" = "yes" ]
}

do_preflight() {
  echo "== preflight =="
  echo "STABLE_RUNTIME=$STABLE_RUNTIME"
  echo "LAUNCHER=$LAUNCHER"
  echo "PLIST=$PLIST"

  # 1. stable runtime is physical file, not symlink
  if [ ! -f "$STABLE_RUNTIME" ]; then
    echo "FAIL: stable runtime not a file: $STABLE_RUNTIME" >&2; return 1
  fi
  if [ -L "$STABLE_RUNTIME" ]; then
    echo "FAIL: stable runtime must be physical file, not symlink: $STABLE_RUNTIME" >&2; return 1
  fi
  echo "OK: stable runtime is physical file"

  # 2. codesign verify strict
  if ! codesign --verify --strict --verbose=4 "$STABLE_RUNTIME" 2>&1; then
    echo "FAIL: codesign --verify --strict failed" >&2; return 1
  fi
  echo "OK: codesign --verify --strict valid"

  # 3. Identifier
  _dv_out=$(codesign -dv --verbose=4 "$STABLE_RUNTIME" 2>&1 || true)
  echo "$_dv_out" | grep -q "Identifier=$EXPECTED_ID" || {
    echo "FAIL: Identifier != $EXPECTED_ID" >&2
    echo "$_dv_out" >&2
    return 1
  }
  echo "OK: Identifier=$EXPECTED_ID"

  # 4. DR
  _dr_out=$(codesign -d -r - "$STABLE_RUNTIME" 2>&1 || true)
  echo "$_dr_out" | grep -qF "$EXPECTED_DR" || {
    echo "FAIL: DR mismatch" >&2
    echo "expected: $EXPECTED_DR" >&2
    echo "got: $_dr_out" >&2
    return 1
  }
  echo "OK: DR matches"

  # 5. shasum for identity (non-secret)
  if command -v shasum >/dev/null 2>&1; then
    _sha=$(shasum -a 256 "$STABLE_RUNTIME" 2>&1 | awk '{print $1}')
    echo "OK: SHA256=$_sha"
  fi

  # 6. launcher / plist exist
  if [ ! -f "$LAUNCHER" ]; then echo "FAIL: launcher missing $LAUNCHER" >&2; return 1; fi
  echo "OK: launcher exists"
  if [ ! -f "$PLIST" ]; then echo "FAIL: plist missing $PLIST" >&2; return 1; fi
  echo "OK: plist exists"

  # 7. domain
  _domain=$(resolve_domain) || return 1
  echo "OK: domain=$_domain"

  # 8. nc / TCP tool
  if ! command -v nc >/dev/null 2>&1; then echo "FAIL: nc not found" >&2; return 1; fi
  echo "OK: nc found at $(command -v nc)"

  # 9. no secret exposure check (we never read config.toml / slug)
  echo "OK: preflight PASS (no secret read, no /health, no /mcp probe)"
  return 0
}

do_activate() {
  echo "== activate =="
  # Re-do preflight under lock
  do_preflight || { echo "FAIL: preflight failed, aborting (no kickstart)" >&2; return 1; }

  _domain=$(resolve_domain) || return 1
  echo "domain=$_domain"

  # Snapshot before (wrapper pid + runs + running child pid)
  _before_pid=$(get_wrapper_pid "$_domain" 2>&1 || true)
  _before_runs=$(get_wrapper_runs "$_domain" 2>&1 || true)
  _before_child_pid=""
  if [ -n "$_before_pid" ] && [ "$_before_pid" != "0" ]; then
    _before_child_pid=$(get_stable_child_pid "$_before_pid" "$STABLE_RUNTIME" 2>&1 || true)
  fi
  echo "before pid=$_before_pid runs=$_before_runs child=${_before_child_pid:-none}"

  # --- content identity decision ---
  # Path-only idempotency is not content identity: the same stable path can hold
  # different bytes (a version upgrade). Compare the staged artifact digest with
  # the current stable runtime digest and promote atomically when they differ.
  _content_upgrade=0
  _staged_sha=""
  if [ -n "${STAGED_RUNTIME:-}" ] && [ -f "$STAGED_RUNTIME" ]; then
    _staged_sha=$(shasum -a 256 "$STAGED_RUNTIME" 2>/dev/null | awk '{print $1}')
    _stable_sha_now=$(shasum -a 256 "$STABLE_RUNTIME" 2>/dev/null | awk '{print $1}')
    echo "staged=$STAGED_RUNTIME sha256=$_staged_sha"
    echo "stable=$STABLE_RUNTIME sha256=$_stable_sha_now"
    if [ "$_staged_sha" != "$_stable_sha_now" ]; then
      _content_upgrade=1
      echo "content upgrade intent: staged bytes differ from the stable runtime"
    else
      echo "staged content identical to the stable runtime — no-op candidate"
    fi
  else
    echo "NOTE: no staged artifact found at ${STAGED_RUNTIME:-unset}; idempotency is path-only for this run"
  fi

  # --- idempotency safety belt (must be before any launcher mutation/kickstart) ---
  # ponytail: idempotency check — launcher precisely stable AND child precisely stable => no kickstart
  # Test hook: CATDESK_TEST_FORCE_ALREADY_ACTIVE=1 forces this branch without touching production launcer
  _idempotent_launcher=0
  _idempotent_child=0
  if [ "$_content_upgrade" -eq 1 ]; then
    echo "check: content upgrade requested — path-only idempotency does not apply"
  elif [ "${CATDESK_TEST_FORCE_ALREADY_ACTIVE:-}" = "1" ]; then
    echo "TEST_HOOK: forcing already-active branch (CATDESK_TEST_FORCE_ALREADY_ACTIVE=1)"
    _idempotent_launcher=1
    _idempotent_child=1
  else
    if is_launcher_stable "$STABLE_RUNTIME" "$LAUNCHER"; then
      echo "check: launcher already precisely points to stable runtime"
      _idempotent_launcher=1
    else
      echo "check: launcher not yet stable"
    fi
    if [ "$_idempotent_launcher" -eq 1 ]; then
      _current_wrapper_pid=$(get_wrapper_pid "$_domain" 2>&1 || true)
      if [ -n "$_current_wrapper_pid" ] && [ "$_current_wrapper_pid" != "0" ]; then
        if _child_pid_probe=$(get_stable_child_pid "$_current_wrapper_pid" "$STABLE_RUNTIME" 2>&1); then
          echo "check: stable child PID $_child_pid_probe already under wrapper $_current_wrapper_pid"
          _idempotent_child=1
          _idempotent_child_pid="$_child_pid_probe"
        else
          echo "check: launcher stable but no stable child under wrapper $_current_wrapper_pid (previous attempt interrupted?)"
        fi
      else
        echo "check: cannot resolve wrapper pid for idempotency check"
      fi
    fi
  fi

  if [ "$_idempotent_launcher" -eq 1 ] && [ "$_idempotent_child" -eq 1 ]; then
    echo "ALREADY_ACTIVE: launcher and child already stable — skipping kickstart"
    # Directly do 30s triple stability + TCP gate (allow test short via CATDESK_TEST_STABILITY_SECS)
    _stability_secs="${CATDESK_TEST_STABILITY_SECS:-30}"
    # Establish baseline from current live state (not from _before)
    _base_wrapper_pid=$(get_wrapper_pid "$_domain" 2>&1 || true)
    _base_runs=$(get_wrapper_runs "$_domain" 2>&1 || true)
    _base_child_pid=$(get_stable_child_pid "$_base_wrapper_pid" "$STABLE_RUNTIME" 2>&1 || true)
    if [ -z "$_base_wrapper_pid" ] || [ -z "$_base_runs" ] || [ -z "$_base_child_pid" ]; then
      echo "FAIL: already-active baseline incomplete (pid=$_base_wrapper_pid runs=$_base_runs child=$_base_child_pid)" >&2
      return 1
    fi
    echo "already-active baseline wrapper pid=$_base_wrapper_pid runs=$_base_runs child pid=$_base_child_pid"
    echo "stability gate: ${_stability_secs}s wrapper PID+runs+child unchanged (already-active)"
    sleep "$_stability_secs"
    _cur_wrapper_pid=$(get_wrapper_pid "$_domain" 2>&1 || true)
    _cur_runs=$(get_wrapper_runs "$_domain" 2>&1 || true)
    _cur_child_pid=$(get_stable_child_pid "$_cur_wrapper_pid" "$STABLE_RUNTIME" 2>&1 || true)
    echo "after ${_stability_secs}s wrapper pid=$_cur_wrapper_pid runs=$_cur_runs child pid=$_cur_child_pid (baseline wrapper=$_base_wrapper_pid runs=$_base_runs child=$_base_child_pid)"
    if [ "$_cur_wrapper_pid" != "$_base_wrapper_pid" ] || [ "$_cur_runs" != "$_base_runs" ] || [ "$_cur_child_pid" != "$_base_child_pid" ]; then
      echo "FAIL: stability gate (already-active) — wrapper PID/runs/child changed (wrapper $_base_wrapper_pid->$_cur_wrapper_pid runs $_base_runs->$_cur_runs child $_base_child_pid->$_cur_child_pid)" >&2
      return 1
    fi
    # Child PPID/exe already verified by get_stable_child_pid (PPID==wrapper && exe==target), but explicit re-check
    if ! get_stable_child_pid "$_cur_wrapper_pid" "$STABLE_RUNTIME" 2>&1 | grep -qx "$_cur_child_pid"; then
      echo "FAIL: already-active child PPID/exe no longer stable" >&2
      return 1
    fi
    echo "OK: ${_stability_secs}s stability PASS (already-active)"
    if ! nc -z 127.0.0.1 3200 2>&1; then
      echo "FAIL: nc -z 127.0.0.1 3200 failed (already-active)" >&2
      return 1
    fi
    echo "OK: nc -z 127.0.0.1 3200 succeeded"
    echo "ALREADY_ACTIVE PASS — no kickstart performed; post-activation acceptance to be done by ChatGPT after reconnect"
    return 0
  fi

  # Not already-active: proceed with backup, atomic launcher edit, single kickstart
  # Backup with private perms
  umask 077
  _ts=$(date +%Y%m%d-%H%M%S)
  BACKUP_DIR="$LOCK_DIR/backups/$_ts-$$"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
  cp -p "$LAUNCHER" "$BACKUP_DIR/catdesk-launch.tcl.bak" 2>&1 || { echo "FAIL: backup launcher" >&2; return 1; }
  cp -p "$PLIST" "$BACKUP_DIR/com.hong.catdesk.plist.bak" 2>&1 || { echo "FAIL: backup plist" >&2; return 1; }
  cp -p "$STABLE_RUNTIME" "$BACKUP_DIR/runtime.catdesk.bak" 2>&1 || { echo "FAIL: backup runtime binary" >&2; return 1; }
  {
    echo "Rollback (fast, local): cp -p \"$BACKUP_DIR/runtime.catdesk.bak\" \"$STABLE_RUNTIME\" then kickstart only com.hong.catdesk."
    echo "Rollback (canonical): re-sign the previous accepted versioned artifact as com.hong.catdesk, atomically replace $STABLE_RUNTIME, then kickstart only com.hong.catdesk."
    echo "Rollback source (previous accepted artifact): ${CATDESK_ROLLBACK_SOURCE:-<record the previous accepted versioned artifact here>}"
    echo "Do not modify Cloudflare or TCC."
  } > "$BACKUP_DIR/ROLLBACK.txt"
  # save metadata
  {
    echo "timestamp=$_ts"
    echo "stable_runtime=$STABLE_RUNTIME"
    echo "staged_runtime=${STAGED_RUNTIME:-none} staged_sha256=${_staged_sha:-none}"
    echo "content_upgrade=$_content_upgrade"
    echo "domain=$_domain"
    echo "before_pid=$_before_pid before_runs=$_before_runs before_child=${_before_child_pid:-none}"
    shasum -a 256 "$STABLE_RUNTIME" 2>&1 || true
    codesign -dv --verbose=4 "$STABLE_RUNTIME" 2>&1 || true
    codesign -d -r - "$STABLE_RUNTIME" 2>&1 || true
    ls -l "$LAUNCHER" 2>&1 || true
    ls -l "$PLIST" 2>&1 || true
  } > "$BACKUP_DIR/meta.txt"
  chmod 600 "$BACKUP_DIR"/* 2>&1 || true
  echo "OK: backup at $BACKUP_DIR"

  # --- content upgrade promotion (atomic rename; the single kickstart follows below) ---
  if [ "$_content_upgrade" -eq 1 ]; then
    echo "== promote staged artifact =="
    if [ ! -f "$STAGED_RUNTIME" ]; then echo "FAIL: staged artifact disappeared: $STAGED_RUNTIME" >&2; return 1; fi
    if [ -L "$STAGED_RUNTIME" ]; then echo "FAIL: staged artifact must be a physical file" >&2; return 1; fi
    if ! codesign --verify --strict --verbose=4 "$STAGED_RUNTIME" 2>&1; then
      echo "FAIL: staged codesign --verify --strict failed (no mutation performed)" >&2
      return 1
    fi
    _staged_dv=$(codesign -dv --verbose=4 "$STAGED_RUNTIME" 2>&1 || true)
    echo "$_staged_dv" | grep -q "Identifier=$EXPECTED_ID" || {
      echo "FAIL: staged Identifier mismatch (no mutation performed)" >&2
      return 1
    }
    _staged_dr=$(codesign -d -r - "$STAGED_RUNTIME" 2>&1 || true)
    echo "$_staged_dr" | grep -qF "$EXPECTED_DR" || {
      echo "FAIL: staged DR mismatch (no mutation performed)" >&2
      return 1
    }
    # Same-filesystem temp + digest check, then atomic rename: a running process keeps
    # its old inode, so an in-place overwrite of the live binary is never used.
    _tmp_new="$(dirname "$STABLE_RUNTIME")/.catdesk-runtime.tmp.$$"
    cp -p "$STAGED_RUNTIME" "$_tmp_new" 2>&1 || { echo "FAIL: staging temp copy" >&2; return 1; }
    _tmp_sha=$(shasum -a 256 "$_tmp_new" 2>/dev/null | awk '{print $1}')
    if [ "$_tmp_sha" != "$_staged_sha" ]; then
      echo "FAIL: staged temp digest mismatch ($_tmp_sha != $_staged_sha)" >&2
      rm -f "$_tmp_new" 2>/dev/null || true
      return 1
    fi
    if ! mv -f "$_tmp_new" "$STABLE_RUNTIME" 2>&1; then
      echo "FAIL: atomic rename into $STABLE_RUNTIME failed" >&2
      rm -f "$_tmp_new" 2>/dev/null || true
      return 1
    fi
    _post_sha=$(shasum -a 256 "$STABLE_RUNTIME" 2>/dev/null | awk '{print $1}')
    if [ "$_post_sha" != "$_staged_sha" ]; then
      echo "FAIL: post-swap digest mismatch ($_post_sha != $_staged_sha)" >&2
      return 1
    fi
    if ! codesign --verify --strict --verbose=4 "$STABLE_RUNTIME" 2>&1; then
      echo "FAIL: post-swap codesign verification failed" >&2
      return 1
    fi
    _post_dr=$(codesign -d -r - "$STABLE_RUNTIME" 2>&1 || true)
    echo "$_post_dr" | grep -qF "$EXPECTED_DR" || { echo "FAIL: post-swap DR mismatch" >&2; return 1; }
    echo "OK: stable runtime atomically replaced (sha256=$_staged_sha)"
  fi

  # Only modify launcher spawn target to canonical stable runtime — atomic replace
  if ! is_launcher_stable "$STABLE_RUNTIME" "$LAUNCHER"; then
    echo "launcher needs update — performing atomic replace"
    _launcher_dir=$(dirname "$LAUNCHER")
    _tmp_launcher="$_launcher_dir/.catdesk-launch.tmp.$$"
    # Ensure exactly one spawn catdesk line — otherwise FAIL and do not write
    _spawn_count=$(grep -cE '^[[:space:]]*spawn[[:space:]]+.*catdesk' "$LAUNCHER" 2>/dev/null || true)
    if [ "$_spawn_count" != "1" ]; then
      echo "FAIL: launcher must contain exactly one spawn catdesk line (found $_spawn_count)" >&2
      echo "HINT: backup retained at $BACKUP_DIR ; no launcher write" >&2
      return 1
    fi
    # Generate temp launcher with precise replacement
    awk -v target="$STABLE_RUNTIME" '
      /^[[:space:]]*spawn[[:space:]]+.*catdesk/ {
        print "spawn " target; replaced=1; next
      }
      { print }
      END { if (replaced!=1) exit 1 }
    ' "$LAUNCHER" > "$_tmp_launcher" || {
      echo "FAIL: launcher edit failed (awk)" >&2
      rm -f "$_tmp_launcher" 2>/dev/null || true
      return 1
    }
    # Verify temp contains exactly one precise spawn target and no other catdesk spawn
    if ! is_launcher_stable "$STABLE_RUNTIME" "$_tmp_launcher"; then
      echo "FAIL: launcher edit verification — temp does not precisely contain stable runtime" >&2
      cat "$_tmp_launcher" >&2 || true
      rm -f "$_tmp_launcher" 2>/dev/null || true
      return 1
    fi
    chmod 755 "$_tmp_launcher" 2>&1 || chmod 700 "$_tmp_launcher" 2>&1 || true
    # Atomic move (same filesystem)
    if ! mv -f "$_tmp_launcher" "$LAUNCHER" 2>&1; then
      echo "FAIL: atomic mv to launcher failed" >&2
      rm -f "$_tmp_launcher" 2>/dev/null || true
      return 1
    fi
    echo "OK: launcher atomically updated to $STABLE_RUNTIME"
  else
    echo "OK: launcher already points to stable runtime (atomic check)"
  fi

  # Exactly ONE kickstart -k — ponytail: no retry, no auto-rollback
  echo "kickstart -k $_domain/com.hong.catdesk (single, no retry)"
  if ! launchctl kickstart -k "$_domain/com.hong.catdesk" 2>&1; then
    echo "FAIL: kickstart failed" >&2
    echo "HINT: backup retained at $BACKUP_DIR ; no auto-rollback performed" >&2
    return 1
  fi
  echo "OK: kickstart issued"

  # Replacement verification — precise: wrapper PID + PPID + exe token exact
  echo "waiting for replacement child..."
  sleep 3
  _post_wrapper_pid=$(get_wrapper_pid "$_domain" 2>&1 || true)
  _found_stable=""
  for _i in 1 2 3 4 5; do
    if _found_stable=$(get_stable_child_pid "$_post_wrapper_pid" "$STABLE_RUNTIME" 2>&1); then
      if [ -n "$_found_stable" ]; then break; fi
    fi
    sleep 2
    _post_wrapper_pid=$(get_wrapper_pid "$_domain" 2>&1 || true)
  done
  if [ -z "$_found_stable" ]; then
    echo "FAIL: replacement verification — no stable child with PPID=$_post_wrapper_pid and exe=$STABLE_RUNTIME" >&2
    ps -axo pid=,ppid=,command= 2>&1 | grep -F catdesk | grep -v grep >&2 || true
    echo "HINT: backup at $BACKUP_DIR ; no second kickstart, no auto-rollback" >&2
    return 1
  fi
  # Content upgrades must prove a *new* process: an unchanged child PID means the
  # promoted bytes were never loaded.
  if [ "$_content_upgrade" -eq 1 ] && [ -n "$_before_child_pid" ] && [ "$_found_stable" = "$_before_child_pid" ]; then
    echo "FAIL: replacement child PID is unchanged ($_found_stable) — promoted content is not proven to be running" >&2
    echo "HINT: backup at $BACKUP_DIR ; no second kickstart, no auto-rollback" >&2
    return 1
  fi
  echo "OK: replacement child PID $_found_stable (PPID=$_post_wrapper_pid exe=$STABLE_RUNTIME)"

  # Baseline for stability: wrapper pid, runs, child pid
  _post_runs=$(get_wrapper_runs "$_domain" 2>&1 || true)
  echo "post pid=$_post_wrapper_pid runs=$_post_runs child=$_found_stable (before pid=$_before_pid runs=$_before_runs)"

  _base_wrapper_pid="$_post_wrapper_pid"
  _base_runs="$_post_runs"
  _base_child_pid="$_found_stable"
  echo "stability gate: 30s wrapper PID+runs+child unchanged (baseline wrapper=$_base_wrapper_pid runs=$_base_runs child=$_base_child_pid)"
  sleep 30
  _cur_wrapper_pid=$(get_wrapper_pid "$_domain" 2>&1 || true)
  _cur_runs=$(get_wrapper_runs "$_domain" 2>&1 || true)
  _cur_child_pid=$(get_stable_child_pid "$_cur_wrapper_pid" "$STABLE_RUNTIME" 2>&1 || true)
  echo "after 30s wrapper pid=$_cur_wrapper_pid runs=$_cur_runs child pid=$_cur_child_pid"
  if [ -z "$_cur_wrapper_pid" ] || [ -z "$_cur_runs" ] || [ -z "$_cur_child_pid" ]; then
    echo "FAIL: stability gate — could not resolve wrapper/runs/child after 30s" >&2
    echo "HINT: backup at $BACKUP_DIR ; no retry, no auto-rollback" >&2
    return 1
  fi
  if [ "$_cur_wrapper_pid" != "$_base_wrapper_pid" ] || [ "$_cur_runs" != "$_base_runs" ] || [ "$_cur_child_pid" != "$_base_child_pid" ]; then
    echo "FAIL: stability gate — wrapper PID/runs/child changed within 30s (wrapper $_base_wrapper_pid->$_cur_wrapper_pid runs $_base_runs->$_cur_runs child $_base_child_pid->$_cur_child_pid)" >&2
    echo "HINT: backup at $BACKUP_DIR ; no retry, no auto-rollback" >&2
    return 1
  fi
  # Extra PPID/exe re-verification (already guaranteed by get_stable_child_pid but explicit)
  if ! get_stable_child_pid "$_cur_wrapper_pid" "$STABLE_RUNTIME" 2>&1 | grep -qx "$_cur_child_pid"; then
    echo "FAIL: stability gate — child PPID/exe no longer matches stable target" >&2
    return 1
  fi
  echo "OK: 30s stability PASS (wrapper+runs+child)"

  # TCP listener check (no /health, no /mcp, no curl) — after stability
  if ! nc -z 127.0.0.1 3200 2>&1; then
    echo "FAIL: nc -z 127.0.0.1 3200 failed" >&2
    return 1
  fi
  echo "OK: nc -z 127.0.0.1 3200 succeeded"

  echo "ACTIVATE PASS — backup at $BACKUP_DIR ; post-activation MCP/Cloudflare acceptance to be done by ChatGPT after reconnect"
  return 0
}

case "$MODE" in
  preflight) do_preflight ;;
  activate) do_activate ;;
  *) echo "ERR: unknown mode $MODE" >&2; exit 2 ;;
esac
