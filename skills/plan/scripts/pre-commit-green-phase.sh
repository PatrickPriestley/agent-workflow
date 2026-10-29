#!/usr/bin/env bash
# pre-commit: during a green step, reject commits that touch the red step's tests.
# Active while <git-dir>/green-phase exists; it lists the protected paths, one per line.
#
# Staged paths come from `git diff --cached --name-only --no-renames -z`: NUL-separated so
# git never quotes them (non-ASCII, tabs, spaces), and without rename detection so a rename
# shows both its old and new path. Fails closed: an unreadable or empty marker, or a git
# error, rejects the commit.
set -uo pipefail
marker="$(git rev-parse --git-dir)/green-phase"
[ -e "$marker" ] || exit 0
exec python3 - "$marker" <<'PY'
import subprocess, sys

marker = sys.argv[1]
try:
    text = open(marker, "rb").read().decode("utf-8", "surrogateescape")
except OSError as e:
    sys.exit(f"green step: cannot read {marker} ({e}); refusing to commit. Ask the engineer.")
protected = {line for line in text.split("\n") if line}
if not protected:
    sys.exit(f"green step: {marker} is empty; refusing to commit. Ask the engineer.")

r = subprocess.run(["git", "diff", "--cached", "--name-only", "--no-renames", "-z"], capture_output=True)
if r.returncode != 0:
    sys.exit("green step: could not list staged paths; refusing to commit: "
             + r.stderr.decode("utf-8", "replace").strip())
staged = {p.decode("utf-8", "surrogateescape") for p in r.stdout.split(b"\0") if p}
touched = sorted(staged & protected)
if touched:
    lines = "\n".join(f"  {p}" for p in touched)
    sys.exit("green step: these tests were committed in the red step and must not change:\n"
             f"{lines}\n"
             "Make the test pass without editing it, or stop and tell the engineer why it must change.")
PY
