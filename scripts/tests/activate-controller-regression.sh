#!/bin/sh
# Regression harness for scripts/activate-stable-runtime.sh.
#
# Runs the controller against fake codesign/launchctl/ps/nc and a private temp
# runtime, then asserts the audit-fixed behaviours:
#   T1  --preflight is read-only: it must not create activation dir or lock state
#   T2  changed bytes at the same stable path => atomic promotion + exactly one kickstart
#   T3  identical bytes at the same stable path => ALREADY_ACTIVE, no kickstart
#   T4  no staged artifact present => path-only idempotency with an explicit notice
#
# Usage: sh scripts/tests/activate-controller-regression.sh
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CONTROLLER="$REPO_ROOT/scripts/activate-stable-runtime.sh"
[ -f "$CONTROLLER" ] || { echo "FAIL: controller not found at $CONTROLLER" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/catdesk-controller-regression.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN" "$TMP/runtime/bin" "$TMP/runtime-next/bin" "$TMP/state"
echo 1 > "$TMP/state/runs"
echo 0 > "$TMP/state/counter"

# --- fake toolchain -------------------------------------------------------
cat > "$FAKEBIN/codesign" <<'EOS'
#!/bin/sh
case "$1" in
  --verify) exit 0 ;;
  -dv)
    printf 'Identifier=com.hong.catdesk\nAuthority=CatDesk Local Code Signing\nTeamIdentifier=not set\n'
    exit 0 ;;
  -d)
    printf 'designated => identifier "com.hong.catdesk" and certificate root = H"7f453106476b0da6b2fedbc4bc6f81b8c9aca51a"\n'
    exit 0 ;;
esac
exit 0
EOS

cat > "$FAKEBIN/launchctl" <<'EOS'
#!/bin/sh
STATE="${CATDESK_FAKE_STATE:?}"
case "$1" in
  print)
    printf 'gui/501/com.hong.catdesk = {\n\tstate = running\n\tpid = 5000\n\truns = %s\n}\n' "$(cat "$STATE/runs")"
    exit 0 ;;
  kickstart)
    printf '%s\n' "$(( $(cat "$STATE/runs") + 1 ))" > "$STATE/runs"
    printf '%s\n' "$(( $(cat "$STATE/counter") + 1 ))" > "$STATE/counter"
    exit 0 ;;
esac
exit 0
EOS

cat > "$FAKEBIN/ps" <<'EOS'
#!/bin/sh
STATE="${CATDESK_FAKE_STATE:?}"
TARGET="${CATDESK_FAKE_TARGET:?}"
CHILD=$(( 9000 + $(cat "$STATE/counter") ))
printf '%s 1 /usr/bin/expect -f %s\n' 5000 "${CATDESK_FAKE_LAUNCHER:-/tmp/launcher.tcl}"
printf '%s 5000 %s\n' "$CHILD" "$TARGET"
EOS

cat > "$FAKEBIN/nc" <<'EOS'
#!/bin/sh
exit 0
EOS

chmod +x "$FAKEBIN/codesign" "$FAKEBIN/launchctl" "$FAKEBIN/ps" "$FAKEBIN/nc"

run_controller() {
  /usr/bin/env -i \
    PATH="$FAKEBIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$TMP/home" \
    CATDESK_STABLE_RUNTIME="$TMP/runtime/bin/catdesk" \
    CATDESK_STAGED_RUNTIME="$TMP/runtime-next/bin/catdesk" \
    CATDESK_LAUNCHER="$TMP/launcher.tcl" \
    CATDESK_PLIST="$TMP/com.hong.catdesk.plist" \
    CATDESK_ACTIVATION_DIR="$TMP/activation" \
    CATDESK_TEST_STABILITY_SECS=1 \
    CATDESK_FAKE_STATE="$TMP/state" \
    CATDESK_FAKE_TARGET="$TMP/runtime/bin/catdesk" \
    CATDESK_FAKE_LAUNCHER="$TMP/launcher.tcl" \
    /bin/sh "$CONTROLLER" "$@"
}

fail() {
  echo "FAIL($1): $2"
  [ -n "${3:-}" ] && [ -f "$3" ] && cat "$3"
  exit 1
}

# --- T1: --preflight must stay read-only ----------------------------------
echo "== T1: --preflight creates no activation state =="
rm -rf "$TMP/activation"
printf 'OLD-BINARY\n' > "$TMP/runtime/bin/catdesk"
printf 'spawn %s\n' "$TMP/runtime/bin/catdesk" > "$TMP/launcher.tcl"
: > "$TMP/com.hong.catdesk.plist"
run_controller --preflight > "$TMP/t1.out" 2>&1 || fail T1 "preflight rc != 0" "$TMP/t1.out"
[ -e "$TMP/activation" ] && fail T1 "preflight created activation state at $TMP/activation" "$TMP/t1.out"
echo "OK(T1): preflight created no activation state"

# --- T2: changed bytes at the same path => promote + one kickstart ---------
echo "== T2: content upgrade promotes atomically and kickstarts exactly once =="
printf 'NEW-BINARY\n' > "$TMP/runtime-next/bin/catdesk"
echo 1 > "$TMP/state/runs"
echo 0 > "$TMP/state/counter"
run_controller --activate > "$TMP/t2.out" 2>&1 || fail T2 "activate rc != 0" "$TMP/t2.out"
grep -q "content upgrade intent" "$TMP/t2.out" || fail T2 "no content upgrade intent" "$TMP/t2.out"
grep -q "atomically replaced" "$TMP/t2.out" || fail T2 "stable runtime was not atomically replaced" "$TMP/t2.out"
[ "$(cat "$TMP/runtime/bin/catdesk")" = "NEW-BINARY" ] || fail T2 "runtime content not replaced"
[ "$(cat "$TMP/state/counter")" = "1" ] || fail T2 "expected exactly one kickstart, got $(cat "$TMP/state/counter")"
grep -q "ALREADY_ACTIVE" "$TMP/t2.out" && fail T2 "wrongly reported ALREADY_ACTIVE for changed bytes" "$TMP/t2.out"
grep -q "replacement child PID 9001" "$TMP/t2.out" || fail T2 "no new-child proof after promotion" "$TMP/t2.out"
for backup in "$TMP/activation/backups/"*/runtime.catdesk.bak; do
  [ -f "$backup" ] || fail T2 "no runtime binary backup taken"
  [ "$(cat "$backup")" = "OLD-BINARY" ] || fail T2 "backup does not hold the previous runtime bytes"
done
echo "OK(T2): atomic promotion + single kickstart + new child proven"

# --- T3: identical bytes => genuine no-op ---------------------------------
echo "== T3: identical content stays a no-op without kickstart =="
printf 'SAME-BINARY\n' > "$TMP/runtime/bin/catdesk"
printf 'SAME-BINARY\n' > "$TMP/runtime-next/bin/catdesk"
echo 1 > "$TMP/state/runs"
echo 0 > "$TMP/state/counter"
run_controller --activate > "$TMP/t3.out" 2>&1 || fail T3 "activate rc != 0" "$TMP/t3.out"
grep -q "ALREADY_ACTIVE" "$TMP/t3.out" || fail T3 "expected ALREADY_ACTIVE for identical bytes" "$TMP/t3.out"
[ "$(cat "$TMP/state/counter")" = "0" ] || fail T3 "kickstart happened on an identical-content no-op"
echo "OK(T3): identical content stayed a no-op"

# --- T4: no staged artifact => explicit path-only notice -------------------
echo "== T4: missing staged artifact falls back with an explicit notice =="
rm -f "$TMP/runtime-next/bin/catdesk"
echo 1 > "$TMP/state/runs"
echo 0 > "$TMP/state/counter"
run_controller --activate > "$TMP/t4.out" 2>&1 || fail T4 "activate rc != 0" "$TMP/t4.out"
grep -q "idempotency is path-only" "$TMP/t4.out" || fail T4 "missing staged-artifact notice" "$TMP/t4.out"
grep -q "ALREADY_ACTIVE" "$TMP/t4.out" || fail T4 "expected path-only ALREADY_ACTIVE" "$TMP/t4.out"
echo "OK(T4): explicit notice emitted on the path-only fallback"

echo "PASS: activate-stable-runtime.sh regression harness (T1-T4)"
