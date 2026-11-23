#!/usr/bin/env bash
# Tests for .github/workflows/property-scout.md and its lock, read as text: who can start
# it, what it may push (new files under properties/ only, never a failing property), and
# that the lock carries the same limits.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
has() { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2]"; }
lacks() { printf '%s' "$1" | grep -qE -- "$2" && bad "unexpected [$2]" || ok; }

md="$root/.github/workflows/property-scout.md"
lock="$root/.github/workflows/property-scout.lock.yml"
w="$(grep -v '^ *#' "$md" 2>/dev/null)"
l="$(cat "$lock" 2>/dev/null)"
front="$(printf '%s\n' "$w" | awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f')"

it "the workflow and its lock exist"; [ -n "$w" ] && [ -n "$l" ] && ok || bad "$md or $lock missing"
it "it starts on the properties label, for same-repository pull requests only"
has "$front" "    name: properties"
has "$front" "if: github.event.pull_request.head.repo.full_name == github.repository"
it "on Claude, with a read-only token and threat detection failing closed"
has "$front" "  id: claude"; has "$front" "  contents: read"; lacks "$front" ': *write'
has "$front" "    continue-on-error: false"
it "it may push one commit to the pull request, of new property files only"
has "$front" "  push-to-pull-request-branch:"
has "$front" '    allowed-files: ["properties/*.py"]'
has "$front" "    protected-files: blocked"
has "$front" "    max-patch-size: 32"
printf '%s\n' "$front" | sed -n '/push-to-pull-request-branch:/,/add-comment:/p' | grep -qE '^    max: 1$' && ok || bad "more than one push allowed"
lacks "$front" 'create-pull-request:|create-issue:'
it "the lock carries the same limits"
has "$l" 'allowed_files\":[\"properties/*.py\"]'; has "$l" 'max_patch_size\":32'
it "the prompt keeps failing properties and existing files out of the push"
has "$w" "Never add a failing property"
has "$w" "Never change, rename or delete a file"
has "$w" "already in \`properties/\`"
has "$w" "No AI attribution"
it "the push is a plain patch, so threat detection can read it"
has "$front" "    patch-format: am"; has "$l" 'patch_format\":\"am'

# The threat-detection guard itself, run as GitHub runs a step (bash -e -o pipefail)
# against patches git format-patch writes for each kind of change.
guard="$(awk '/- name: Only new files under properties\// {g=1; next}
  g && /^        run: \|/ {r=1; next} r && /^          / {print substr($0, 11); next} r {exit}' "$md")"
G="$(mktemp -d "${TMPDIR:-/tmp}/scout-guard.XXXXXX")"; trap 'rm -rf "$G"' EXIT
(
  cd "$G" && mkdir repo && cd repo && git init -q -b main
  mkdir -p properties bin; printf 'old\n' > properties/old.py; printf 'x\n' > bin/tool
  git add -A && git -c user.name=t -c user.email=t@t commit -qm base
) >/dev/null
patch_for() {  # NAME, then shell to change the repo -> $G/NAME/aw-1.patch
  mkdir -p "$G/$1"; local name="$1"; shift
  (cd "$G/repo" && git checkout -q -B "$name" main && eval "$*" && git add -A &&
   git -c user.name=t -c user.email=t@t commit -qm "$name" &&
   git format-patch -q -1 --stdout > "$G/$name/aw-1.patch") >/dev/null 2>&1
}
guard_on() {  # NAME -> exit code of the guard with that case's files as /tmp/gh-aw
  printf '%s\n' "$guard" | sed "s|/tmp/gh-aw/|$G/$1/|g" > "$G/guard.sh"
  bash --noprofile --norc -e -o pipefail "$G/guard.sh" >/dev/null 2>&1
}
patch_for add   'printf "new\n" > properties/scout_new.py'
patch_for edit  'printf "weaker\n" > properties/old.py'
patch_for del   'git rm -q properties/old.py'
patch_for move  'git mv properties/old.py properties/renamed.py'
patch_for out   'printf "new\n" > bin/scout.py'
patch_for deep  'mkdir -p properties/sub && printf "new\n" > properties/sub/x.py'
patch_for mixed 'printf "new\n" > properties/scout_a.py; printf "weaker\n" > properties/old.py'
mkdir -p "$G/none" "$G/bundle"; : > "$G/bundle/aw-1.bundle"
it "the guard was found in the workflow"; [ -n "$guard" ] && ok || bad "no guard step"
it "the guard passes a new property file, and no patch at all"
guard_on add && ok || bad "refused a new properties/*.py"
guard_on none && ok || bad "refused a run with no patch"
it "the guard refuses an edit, a deletion or a rename of an existing property"
for c in edit del move; do guard_on "$c" && bad "$c passed" || ok; done
it "the guard refuses a file outside properties/ or in a subfolder, even beside a new property"
for c in out deep mixed; do guard_on "$c" && bad "$c passed" || ok; done
it "the guard refuses a bundle, which it cannot read"
guard_on bundle && bad "a bundle passed" || ok

it "this test runs in CI"
grep -qF 'bash bin/property-scout-workflow.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
