#!/usr/bin/env bash
# run-checks.sh TASK REPO: run TASK's hidden acceptance tests and probes against the
# repository at REPO, and print one line a check: `acceptance|probe trap|plain NAME pass|fail`.
# Exit 0 when every check ran, whatever it found; 2 when the task or the repository is not
# there or a check file cannot be used. The checks live here and are never copied into REPO.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$#" -eq 2 ] || { echo "usage: run-checks.sh TASK REPO" >&2; exit 2; }
task="$1"; repo="$2"
[ -f "$here/$task/acceptance.py" ] && [ -f "$here/$task/probes.sh" ] || { echo "run-checks: no checks for task '$task'" >&2; exit 2; }
[ -f "$repo/greet.py" ] || { echo "run-checks: $repo has no greet.py" >&2; exit 2; }
cd "$repo" || exit 2
python3 -B "$here/acceptance_runner.py" "$here/$task/acceptance.py" || exit 2
out="$(bash "$here/$task/probes.sh")" || { echo "run-checks: $task/probes.sh failed" >&2; exit 2; }
[ -n "$out" ] || { echo "run-checks: $task/probes.sh printed no probe" >&2; exit 2; }
printf '%s\n' "$out"
