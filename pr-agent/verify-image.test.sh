#!/usr/bin/env bash
# Tests for pr-agent/verify-image.py against a stub pr_agent package. The stub's filter applies
# PR-Agent's rule (fnmatch.translate, re.match, a "**/" glob also in its root form); STUB_*
# variables break one part at a time. The real check is the workflow step that runs the script
# inside the pinned image.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $1"; }

S="$TMPROOT/stub/pr_agent/algo"; mkdir -p "$S"
: > "$TMPROOT/stub/pr_agent/__init__.py"; : > "$S/__init__.py"
cat > "$TMPROOT/stub/pr_agent/config_loader.py" <<'PY'
import json, os
class _NS:
    def __init__(self, **kw): self.__dict__.update(kw)
def _value(name):
    raw = os.environ.get(name, "[]")
    return raw if os.environ.get("STUB_AS_STRING") == name else json.loads(raw)
_store = {}
class _Settings(_NS):
    def set(self, key, value): _store[key] = value
    def get(self, key, default=None): return _store.get(key, default)
def get_settings():
    return _Settings(ignore=_NS(glob=_value("IGNORE__GLOB")), skills=_NS(paths=_value("SKILLS__PATHS")))
PY
cat > "$S/file_filter.py" <<'PY'
import fnmatch, os, re
from pr_agent.config_loader import get_settings
def filter_ignored(files, platform="github"):
    globs = get_settings().ignore.glob
    if isinstance(globs, str):
        globs = [g.strip() for g in globs.strip("[]").split(",") if g.strip()]
    forms = [f for g in globs for f in ([g, g[3:]] if g.startswith("**/") else [g])]
    if os.environ.get("STUB_DROP_ALL"):
        return []
    return [f for f in files if not any(re.match(fnmatch.translate(p), f.filename) for p in forms)]
PY
cat > "$S/skills_loader.py" <<'PY'
import os
def get_skills_context():
    return "" if os.environ.get("STUB_NO_SKILL") else "## workflow-review\nUse when reviewing..."
PY

mkdir -p "$TMPROOT/stub/pr_agent/git_providers"; : > "$TMPROOT/stub/pr_agent/git_providers/__init__.py"
cat > "$TMPROOT/stub/pr_agent/git_providers/plain_diff_provider.py" <<'PY'
import os, re
from pr_agent.algo.file_filter import filter_ignored
from pr_agent.config_loader import get_settings
class _File:
    def __init__(self, filename, patch): self.filename, self.patch = filename, patch
class PlainDiffGitProvider:
    def get_diff_files(self):
        text = get_settings().get("plain_diff.content")
        files = [_File(m.group(1), m.group(0)) for m in re.finditer(r"diff --git a/(\S+) b/\S+\n(?:(?!diff --git).*\n?)*", text)]
        return files if os.environ.get("STUB_PLAIN_NO_FILTER") else filter_ignored(files, platform="plain_diff")
PY
cat > "$TMPROOT/stub/pr_agent/cli.py" <<'PY'
import os, sys
flags = ["--stdin", "--diff-file", "--output", "--json-output"]
if os.environ.get("STUB_NO_STDIN"):
    flags.remove("--stdin")
if "--help" in sys.argv:
    print("usage: cli.py [-h] " + " ".join(f"[{f}]" for f in flags) + " command")
    sys.exit(0)
sys.exit(2)
PY

globs="$(python3 -I -c 'import json,tomllib; print(json.dumps(tomllib.load(open("'"$root"'/.pr_agent.toml","rb"))["ignore"]["glob"]))')"
run() { env IGNORE__GLOB="$globs" SKILLS__PATHS='["/github/workspace/pr-agent/skills"]' PYTHONPATH="$TMPROOT/stub" "$@" python3 "$here/verify-image.py" 2>&1; }

it "passes when the globs filter every secret, keep ordinary paths, and the skill loads"
out=$(run); rc=$?
[ "$rc" = 0 ] && ok || bad "exit $rc: $out"; has "$out" "verify-image: ok"

it "fails when IGNORE__GLOB arrives as a string"
out=$(run STUB_AS_STRING=IGNORE__GLOB); rc=$?
[ "$rc" = 1 ] && ok || bad "exit $rc"; has "$out" "ignore.glob is a str"

it "fails when SKILLS__PATHS arrives as a string"
out=$(run STUB_AS_STRING=SKILLS__PATHS); rc=$?
[ "$rc" = 1 ] && ok || bad "exit $rc"; has "$out" "skills.paths is a str"

it "fails when a secret path survives the filter"
out=$(env IGNORE__GLOB='["vendor/**"]' SKILLS__PATHS='[]' PYTHONPATH="$TMPROOT/stub" python3 "$here/verify-image.py" 2>&1); rc=$?
[ "$rc" = 1 ] && ok || bad "exit $rc"; has "$out" "secret paths not filtered: .env"

it "fails when ordinary paths are filtered too"
out=$(run STUB_DROP_ALL=1); rc=$?
[ "$rc" = 1 ] && ok || bad "exit $rc"; has "$out" "ordinary paths filtered: README.md"

it "fails when the skill is not in the skills context"
out=$(run STUB_NO_SKILL=1); rc=$?
[ "$rc" = 1 ] && ok || bad "exit $rc"; has "$out" "workflow-review skill is not in"

it "fails when PR-Agent's CLI lacks a flag try.sh passes"
out=$(run STUB_NO_STDIN=1); rc=$?
[ "$rc" = 1 ] && ok || bad "exit $rc"; has "$out" "CLI lacks --stdin"

it "fails when plain-diff mode (the path try.sh uses) lets a secret file through"
out=$(run STUB_PLAIN_NO_FILTER=1); rc=$?
[ "$rc" = 1 ] && ok || bad "exit $rc"; has "$out" "plain-diff mode kept secret paths: .env"

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" = 0 ]
