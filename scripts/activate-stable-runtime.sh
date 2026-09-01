#!/bin/sh
# CatDesk stable-runtime Phase B controller — process-level activation only.
# - No secret handling, no MCP discover, no /health or /mcp hardcoding.
# - Single kickstart, no retry, no auto-rollback, no Cloudflare/TCC mutation.
# - Uses /usr/bin/lockf for single-flight (macOS has no flock).
# - Default mode is --preflight (safe, read-only). --activate is explicit.
set -eu

STABLE_RUNTIME_DEFAULT="/Users/hong/.local/share/catdesk/runtime/bin/catdesk"
STABLE_RUNTIME="${CATDESK_STABLE_RUNTIME:-$STABLE_RUNTIME_DEFAULT}"
LAUNCHER="${CATDESK_LAUNCHER:-/Users/hong/.local/share/catdesk/catdesk-launch.tcl}"
PLIST="${CATDESK_PLIST:-/Users/hong/Library/LaunchAgents/com.hong.catdesk.plist}"
LOCK_DIR="${CATDESK_ACTIVATION_DIR:-$HOME/.catdesk/activation}"
LOCK_FILE="$LOCK_DIR/activate.lock"
EXPECTED_DR='identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"'
EXPECTED_ID="com.hong.catdesk"

# --- single-flight via lockf re-exec (macOS lockf, not flock) ---
# Must be BEFORE arg parsing so we can re-exec with original args ($@).
# Second concurrent instance fails immediately (busy, nonzero) not queue.
if [ -z "${CATDESK_ACTIVATE_LOCKED:-}" ]; then
  umask 077
  mkdir -p "$LOCK_DIR"
  chmod 700 "$LOCK_DIR" 2>/dev/null || true
  : > "$LOCK_FILE" 2>/dev/null || touch "$LOCK_FILE"
  chmod 600 "$LOCK_FILE" 2>/dev/null || true
  # Preserve original args; default to --preflight if none
  # Use -k to keep lock file (0700/0600) and guarantee ordering; -t 0 = fail immediately if busy
  if [ $# -eq 0 ]; then
    CATDESK_ACTIVATE_LOCKED=1 exec /usr/bin/lockf -k -t 0 "$LOCK_FILE" "$0" --preflight
  else
    CATDESK_ACTIVATE_LOCKED=1 exec /usr/bin/lockf -k -t 0 "$LOCK_FILE" "$0" "$@"
  fi
fi

MODE=""
# --- arg parse (now we are already under lock) ---
while [ $# -gt 0 ]; do
  case "$1" in
    --preflight) MODE="preflight"; shift ;;
    --activate) MODE="activate"; shift ;;
    --stable-runtime)
      if [ $# -lt 2 ]; then echo "ERR: --stable-runtime requires path" >&2; exit 2; fi
      STABLE_RUNTIME="$2"; shift 2 ;;
    --stable-runtime=*) STABLE_RUNTIME="${1#--stable-runtime=}"; shift ;;
    -h|--help)
      cat <<HELP
Usage: $0 [--preflight] [--activate] [--stable-runtime PATH]
  No flags      -> --preflight only (safe default, no mutation)
  --preflight   -> read-only gates, no production mutation
  --activate    -> lock, preflight, backup, single kickstart, 30s stability + TCP check
  --stable-runtime PATH -> override canonical stable runtime (default: $STABLE_RUNTIME_DEFAULT)
HELP
      exit 0 ;;
    *) echo "ERR: unknown arg $1" >&2; exit 2 ;;
  esac
done
if [ -z "$MODE" ]; then MODE="preflight"; fi

# From here we are holding the lock.

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

  # Snapshot before
  _before_pid=$(launchctl print "$_domain/com.hong.catdesk" 2>&1 | awk '/^[[:space:]]*pid =/ {print $3}')
  _before_runs=$(launchctl print "$_domain/com.hong.catdesk" 2>&1 | awk '/^[[:space:]]*runs =/ {print $3}')
  echo "before pid=$_before_pid runs=$_before_runs"

  # Backup with private perms
  umask 077
  _ts=$(date +%Y%m%d-%H%M%S)
  BACKUP_DIR="$LOCK_DIR/backups/$_ts-$$"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
  cp -p "$LAUNCHER" "$BACKUP_DIR/catdesk-launch.tcl.bak" 2>&1 || { echo "FAIL: backup launcher" >&2; return 1; }
  cp -p "$PLIST" "$BACKUP_DIR/com.hong.catdesk.plist.bak" 2>&1 || { echo "FAIL: backup plist" >&2; return 1; }
  # save metadata
  {
    echo "timestamp=$_ts"
    echo "stable_runtime=$STABLE_RUNTIME"
    echo "domain=$_domain"
    echo "before_pid=$_before_pid before_runs=$_before_runs"
    shasum -a 256 "$STABLE_RUNTIME" 2>&1 || true
    codesign -dv --verbose=4 "$STABLE_RUNTIME" 2>&1 || true
    codesign -d -r - "$STABLE_RUNTIME" 2>&1 || true
    ls -l "$LAUNCHER" 2>&1 || true
    ls -l "$PLIST" 2>&1 || true
  } > "$BACKUP_DIR/meta.txt"
  chmod 600 "$BACKUP_DIR"/* 2>&1 || true
  echo "OK: backup at $BACKUP_DIR"

  # Only modify launcher spawn target to canonical stable runtime
  # macOS sed -i '' ; replace any versioned or old path containing catdesk/.../bin/catdesk with stable path
  # The launcher line is: spawn /Users/hong/.local/share/catdesk/.../bin/catdesk
  if ! grep -qF "$STABLE_RUNTIME" "$LAUNCHER"; then
    # Replace spawn target
    # Use portable approach: create tmp then mv
    _tmp_launcher="$BACKUP_DIR/launcher.tmp"
    # Replace first occurrence of spawn <path> with spawn STABLE_RUNTIME
    # Keep rest of file intact
    sed "s|spawn .*catdesk|spawn $STABLE_RUNTIME|g" "$LAUNCHER" > "$_tmp_launcher"
    # Verify tmp contains stable path
    if ! grep -qF "$STABLE_RUNTIME" "$_tmp_launcher"; then
      echo "FAIL: launcher edit did not inject stable runtime" >&2; return 1
    fi
    cat "$_tmp_launcher" > "$LAUNCHER"
    chmod 755 "$LAUNCHER" 2>&1 || chmod 700 "$LAUNCHER" 2>&1 || true
    echo "OK: launcher updated to $STABLE_RUNTIME"
  else
    echo "OK: launcher already points to stable runtime"
  fi

  # Exactly ONE kickstart -k
  echo "kickstart -k $_domain/com.hong.catdesk (single, no retry)"
  if ! launchctl kickstart -k "$_domain/com.hong.catdesk" 2>&1; then
    echo "FAIL: kickstart failed" >&2
    echo "HINT: backup retained at $BACKUP_DIR ; no auto-rollback performed" >&2
    return 1
  fi
  echo "OK: kickstart issued"

  # Replacement verification
  echo "waiting for replacement child..."
  sleep 3
  # Confirm new catdesk executable path is stable runtime (macOS ps way)
  _found_stable=0
  for _i in 1 2 3 4 5; do
    if ps aux 2>&1 | grep -F "$STABLE_RUNTIME" | grep -v grep | grep -q catdesk; then
      _found_stable=1; break
    fi
    sleep 2
  done
  if [ "$_found_stable" -eq 0 ]; then
    echo "FAIL: replacement verification — no catdesk process with stable path $STABLE_RUNTIME" >&2
    ps aux 2>&1 | grep catdesk | grep -v grep >&2 || true
    echo "HINT: backup at $BACKUP_DIR ; no second kickstart, no auto-rollback" >&2
    return 1
  fi
  echo "OK: replacement child shows stable runtime path"

  # Also verify via launchctl pid changed or child presence
  _post_pid=$(launchctl print "$_domain/com.hong.catdesk" 2>&1 | awk '/^[[:space:]]*pid =/ {print $3}')
  _post_runs=$(launchctl print "$_domain/com.hong.catdesk" 2>&1 | awk '/^[[:space:]]*runs =/ {print $3}')
  echo "post pid=$_post_pid runs=$_post_runs (before pid=$_before_pid runs=$_before_runs)"

  # 30s PID+runs stability: baseline is post-restart
  _base_pid="$_post_pid"
  _base_runs="$_post_runs"
  echo "stability gate: 30s PID+runs unchanged (baseline pid=$_base_pid runs=$_base_runs)"
  sleep 30
  _cur_pid=$(launchctl print "$_domain/com.hong.catdesk" 2>&1 | awk '/^[[:space:]]*pid =/ {print $3}')
  _cur_runs=$(launchctl print "$_domain/com.hong.catdesk" 2>&1 | awk '/^[[:space:]]*runs =/ {print $3}')
  echo "after 30s pid=$_cur_pid runs=$_cur_runs"
  if [ "$_cur_pid" != "$_base_pid" ] || [ "$_cur_runs" != "$_base_runs" ]; then
    echo "FAIL: stability gate — PID or runs changed within 30s (pid $_base_pid->$_cur_pid runs $_base_runs->$_cur_runs)" >&2
    echo "HINT: backup at $BACKUP_DIR ; no retry, no auto-rollback" >&2
    return 1
  fi
  echo "OK: 30s stability PASS"

  # TCP listener check (no /health, no /mcp, no curl)
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
