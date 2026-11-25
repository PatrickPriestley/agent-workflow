#!/usr/bin/env bash
# Tests for bin/probe-properties: a silent probe must leave the repository's existing
# properties for its file holding (#69 was meant to be silent, but properties/commit_gate.py
# caught it). Docker is stubbed: it runs the command here and records its arguments.
#   bash bin/probe-properties.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/probe-properties.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT

mkdir -p "$T/bin"
cat > "$T/bin/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
if [ "$1" = build ]; then cat > /dev/null; [ -z "${STUB_BUILD_FAILS:-}" ]; exit; fi
shift; src=""; dst=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -v) src="${2%%:*}"; rest="${2#*:}"; dst="${rest%%:*}"; shift 2 ;;
    -e|-u|-w|--network|--tmpfs|--pids-limit|--memory) shift 2 ;;
    --rm|--read-only) shift ;;
    probe-props) shift; break ;;
    *) shift ;;
  esac
done
[ "${1:-}" = timeout ] && shift 2
args=(); for a in "$@"; do args+=("${a/#$dst/$src}"); done
[ "${args[0]:-}" = python ] && args[0]=python3
exec "${args[@]}"
STUB
chmod +x "$T/bin/docker"

# A repository with bin/tool, a property that names it and holds, one that names another file.
R="$T/repo"; mkdir -p "$R/bin" "$R/properties"
printf 'x\n' > "$R/bin/tool"; printf 'y\n' > "$R/bin/other"
printf '# checks bin/tool\nprint("tool: properties held")\n' > "$R/properties/tool.py"
printf '# checks bin/other\nraise SystemExit(1)\n' > "$R/properties/other.py"
git -C "$R" init -q -b main && git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -qm base
key() { printf '{"loud": %s, "file": "%s"}' "$1" "$2" > "$T/key.json"; }
run() {  # -> $rc, output in $T/out, docker calls in $T/docker.log
  : > "$T/docker.log"
  PATH="$T/bin:$PATH" STUB_LOG="$T/docker.log" STUB_BUILD_FAILS="${BUILD_FAILS:-}" \
    bash "$here/probe-properties" "$T/key.json" "$R" > "$T/out" 2>&1; rc=$?
}

it "a silent probe whose file's properties hold passes, and runs only the properties naming it"
key false bin/tool; run; assert_eq 0 "$rc"
assert_eq 1 "$(grep -c '^run ' "$T/docker.log")"
grep -q 'properties/tool.py' "$T/docker.log" && ok || bad "$(cat "$T/docker.log")"
it "a silent probe that breaks a property naming its file is refused, and the property named"
key false bin/other; run; assert_eq 1 "$rc"
grep -qF 'properties/other.py' "$T/out" && grep -q 'not silent' "$T/out" && ok || bad "$(cat "$T/out")"
it "a property that exits 0 without saying it held does not count as holding"
printf '# checks bin/tool\nprint("ok")\n' > "$R/properties/tool.py"
key false bin/tool; run; assert_eq 1 "$rc"
printf '# checks bin/tool\nprint("tool: properties held")\n' > "$R/properties/tool.py"
it "a loud probe, or a file no property names, runs nothing"
key true bin/other; run; assert_eq "0 0" "$rc $(grep -c . "$T/docker.log")"
printf 'z\n' > "$R/bin/lonely"; key false bin/lonely; run; assert_eq "0 0" "$rc $(grep -c . "$T/docker.log")"
grep -q 'no property names bin/lonely' "$T/out" && ok || bad "$(cat "$T/out")"
it "an image that does not build refuses the probe rather than passing it"
key false bin/tool; BUILD_FAILS=1 run; assert_eq 1 "$rc"
it "the properties run with no network, a read-only source, a time limit and the pinned image"
key false bin/tool; run
grep -q -- '--network none' "$T/docker.log" && grep -q -- '--read-only' "$T/docker.log" && grep -q ':/w:ro' "$T/docker.log" && ok || bad "$(cat "$T/docker.log")"
grep -q 'timeout 300 python -I /w/properties/tool.py' "$T/docker.log" && ok || bad "no time limit"
pin="$(grep -o 'python:3.12-slim@sha256:[0-9a-f]*' "$here/../.github/workflows/property-scout.md" | head -1)"
[ -n "$pin" ] && grep -qF "$pin" "$here/probe-properties" && ok || bad "not Property Scout's pinned image [$pin]"
it "a bad key or missing repository is a usage error"
printf '{' > "$T/key.json"; run; assert_eq 2 "$rc"
key false bin/tool; PATH="$T/bin:$PATH" STUB_LOG=/dev/null bash "$here/probe-properties" "$T/key.json" "$T/nowhere" >/dev/null 2>&1; assert_eq 2 "$?"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
