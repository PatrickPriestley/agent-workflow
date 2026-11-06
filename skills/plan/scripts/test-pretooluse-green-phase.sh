#!/usr/bin/env bash
# Tests for pretooluse-green-phase.py. Run: bash test-pretooluse-green-phase.sh
set -u
hook="$(cd "$(dirname "$0")" && pwd)/pretooluse-green-phase.py"
fail=0
repo=$(mktemp -d); trap 'rm -rf "$repo" "$plain"' EXIT
plain=$(mktemp -d)
repo=$(cd "$repo" && pwd -P); plain=$(cd "$plain" && pwd -P)
git -C "$repo" init -q; mkdir -p "$repo/test" "$repo/src"
printf 'test/a.test.ts\n' > "$repo/.git/green-phase"

# expect <name> <exit code> <tool_name> <tool_input json> [cwd]
# Env: REASON (text a block must mention, default the test path), PANE (the hook's
# HERDR_PANE_ID; unset by default).
expect() {
  local want=$2 cwd=${5:-$repo} got reason=${REASON:-test/a.test.ts}
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"%s","tool_input":%s}' \
    "$cwd" "$3" "$4" | env -u HERDR_PANE_ID ${PANE:+HERDR_PANE_ID=$PANE} python3 "$hook" \
    >/dev/null 2>"$repo.err"; got=$?
  if [ "$got" = "$want" ]; then echo "ok   $1"; else echo "FAIL $1 (exit $got, want $want)"; fail=1; fi
  if [ "$want" = 2 ] && [ "$got" = 2 ] && ! grep -q "$reason" "$repo.err"; then
    echo "FAIL $1: block reason does not mention $reason"; fail=1; fi
}
ABS="$repo/test/a.test.ts"
expect "claude Edit of a protected test is blocked"   2 Edit  "{\"file_path\":\"$ABS\",\"old_string\":\"a\",\"new_string\":\"b\"}"
expect "claude Write of a protected test is blocked"  2 Write "{\"file_path\":\"$ABS\",\"content\":\"x\"}"
expect "claude Write of source is allowed"            0 Write "{\"file_path\":\"$repo/src/a.ts\",\"content\":\"x\"}"
expect "claude Read of a protected test is allowed"   0 Read  "{\"file_path\":\"$ABS\"}"
expect "codex apply_patch updating a test is blocked" 2 apply_patch "{\"command\":\"*** Begin Patch\\n*** Update File: $ABS\\n@@\\n-a\\n+b\\n*** End Patch\"}"
expect "codex apply_patch, test second, relative"     2 apply_patch "{\"command\":\"*** Begin Patch\\n*** Update File: src/a.ts\\n@@\\n-a\\n+b\\n*** Delete File: test/a.test.ts\\n*** End Patch\"}"
expect "codex apply_patch of source only is allowed"  0 apply_patch "{\"command\":\"*** Begin Patch\\n*** Add File: src/b.ts\\n+x\\n*** End Patch\"}"
expect "codex apply_patch moving source onto a test"  2 apply_patch "{\"command\":\"*** Begin Patch\\n*** Update File: src/a.ts\\n*** Move to: test/a.test.ts\\n*** End Patch\"}"
expect "Edit with no file_path is allowed, not a crash" 0 Edit "{}"
expect "shell write naming the test by absolute path"   2 Bash  "{\"command\":\"echo x > $ABS\"}"
expect "shell sed -i on a test is blocked"            2 Bash  "{\"command\":\"sed -i '' s/a/b/ test/a.test.ts\"}"
expect "shell redirect into a test is blocked"        2 Bash  "{\"command\":\"echo x > test/a.test.ts\"}"
expect "shell running the test is allowed"            0 Bash  "{\"command\":\"node --import tsx --test test/a.test.ts\"}"
expect "shell reading the test is allowed"            0 Bash  "{\"command\":\"cat test/a.test.ts | head\"}"
expect "outside a git repo, everything is allowed"    0 Write "{\"file_path\":\"$plain/test/a.test.ts\",\"content\":\"x\"}" "$plain"
# The marker itself: only the owning pane may change it while it exists.
MARK="$repo/.git/green-phase"; printf 'w9:p1\n' > "$repo/.git/green-phase.owner"
REASON=green-phase expect "shell rm of the marker is blocked"            2 Bash  "{\"command\":\"rm -f .git/green-phase\"}"
REASON=green-phase expect "shell rm via rev-parse is blocked"            2 Bash  "{\"command\":\"rm \\\"\$(git rev-parse --git-dir)/green-phase\\\"\"}"
REASON=green-phase expect "Write to the marker is blocked"               2 Write "{\"file_path\":\"$MARK\",\"content\":\"\"}"
REASON=green-phase expect "Write to the owner file is blocked"           2 Write "{\"file_path\":\"$MARK.owner\",\"content\":\"w1:p1\"}"
REASON=green-phase expect "apply_patch deleting the marker is blocked"   2 apply_patch "{\"command\":\"*** Begin Patch\\n*** Delete File: .git/green-phase\\n*** End Patch\"}"
REASON=green-phase expect "running the phase helper is blocked"          2 Bash  "{\"command\":\"herd-sdlc phase off\"}"
REASON=green-phase expect "the installed herd-sdlc-phase helper is blocked" 2 Bash "{\"command\":\"herd-sdlc-phase off 0001-x --run r --step 1\"}"
REASON=green-phase expect "the helper script by path is blocked"         2 Bash  "{\"command\":\"bash ~/Code/herd-tools/helpers/herd-sdlc-phase.sh off 0001-x\"}"
expect "an unrelated herd-sdlc command is not mistaken for the helper"   0 Bash  "{\"command\":\"herd-sdlc-ctx spec 0001-x\"}"
REASON=green-phase PANE=w5:p2 expect "another pane cannot clear the marker" 2 Bash "{\"command\":\"rm .git/green-phase\"}"
REASON="conductor's pane (w9:p1)" PANE=w5:p2 expect "with Herdr, the block names the conductor's pane" 2 Bash "{\"command\":\"rm .git/green-phase\"}"
PANE=w9:p1 expect "the owner pane may clear the marker"                  0 Bash  "{\"command\":\"rm .git/green-phase .git/green-phase.owner\"}"
PANE=w9:p1 expect "the owner pane still cannot edit the tests"            2 Edit  "{\"file_path\":\"$ABS\",\"old_string\":\"a\",\"new_string\":\"b\"}"
expect "reading the marker is allowed"                                   0 Bash  "{\"command\":\"cat .git/green-phase\"}"
expect "a file named green-phase outside .git is not the marker"         0 Write "{\"file_path\":\"$repo/src/green-phase-notes.md\",\"content\":\"x\"}"
rm "$repo/.git/green-phase.owner"
REASON=green-phase expect "no owner file, outside Herdr: marker is locked" 2 Bash "{\"command\":\"rm .git/green-phase\"}"
REASON="from their own terminal" expect "without Herdr, the block tells the person to clear the marker themselves" 2 Bash "{\"command\":\"rm .git/green-phase\"}"
expect_quiet_conductor() {  # without an owner file, the refusal does not talk about a Herdr conductor
  printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":"rm .git/green-phase"}}' "$repo" \
    | env -u HERDR_PANE_ID python3 "$hook" >/dev/null 2>"$repo.err"
  if grep -qi -e conductor -e pane "$repo.err"; then echo "FAIL without Herdr, the refusal mentions a conductor or pane"; fail=1
  else echo "ok   without Herdr, the refusal does not mention a conductor or pane"; fi
}
expect_quiet_conductor
rm "$repo/.git/green-phase"
expect "without a marker, creating one is allowed"                       0 Write "{\"file_path\":\"$MARK\",\"content\":\"test/a.test.ts\"}"
expect "without green-phase, test edits are allowed"  0 Edit  "{\"file_path\":\"$ABS\",\"old_string\":\"a\",\"new_string\":\"b\"}"
rm -f "$repo.err"
exit $fail
