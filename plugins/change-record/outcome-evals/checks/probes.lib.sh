# Sourced by each task's probes.sh, which runs in the repository under test. A probe runs the
# real program on one input and prints one line: `probe trap|plain NAME pass|fail`.
export PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8
PROBE_ERR="$(mktemp)" || exit 2
trap 'rm -f "$PROBE_ERR"' EXIT

# refuses KIND NAME PATTERN -- CMD...: the usage-error convention. Passes when CMD exits 2,
# its standard error matches PATTERN (extended, any case), and there is no traceback.
refuses() {
  local kind="$1" name="$2" pat="$3" rc verdict=fail; shift 4
  "$@" > /dev/null 2> "$PROBE_ERR" < /dev/null; rc=$?
  if [ "$rc" -eq 2 ] && grep -Eqi -e "$pat" "$PROBE_ERR" && ! grep -q "Traceback" "$PROBE_ERR"; then verdict=pass; fi
  printf 'probe %s %s %s\n' "$kind" "$name" "$verdict"
}

# holds KIND NAME -- CMD...: passes when CMD exits 0.
holds() {
  local kind="$1" name="$2" verdict=fail; shift 3
  if "$@" > /dev/null 2>&1 < /dev/null; then verdict=pass; fi
  printf 'probe %s %s %s\n' "$kind" "$name" "$verdict"
}
