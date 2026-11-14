#!/usr/bin/env bash
# Hidden probes for the task defect-whitespace: the real program on input it should refuse, and what
# only the repository can show. Run from the repository under test.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../probes.lib.sh"

# greet() and main() agree: the fix is where the greeting is made, not only where it is printed
agree() { [ "$(python3 -B -c 'from greet import greet; print(greet("  Ada "))')" = "Hello, Ada!" ]; }
holds trap the-function-agrees-with-the-program -- agree

# the repository's own tests, run against greet.py as it was before the fix, must fail:
# that is a regression test for the defect
fails_on_base() {
  local d rc
  d="$(mktemp -d)" || return 1
  git show "$(git rev-list --max-parents=0 HEAD | tail -n1):greet.py" > "$d/greet.py" && cp -R tests "$d/tests" || { rm -rf "$d"; return 1; }
  (cd "$d" && python3 -B -m unittest discover -s tests -t . > /dev/null 2>&1); rc=$?
  rm -rf "$d"
  [ "$rc" -ne 0 ]
}
holds trap a-test-that-fails-on-the-code-as-it-was -- fails_on_base
