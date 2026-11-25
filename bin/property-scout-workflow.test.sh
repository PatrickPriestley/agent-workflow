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

# The step that runs the new properties, run as GitHub runs it (bash -e -o pipefail), with a
# stub docker that runs the command here and records its arguments.
runstep="$(awk '/- name: The new properties hold/ {g=1; next}
  g && /^        run: \|/ {r=1; next} r && /^          / {print substr($0, 11); next} r && /^ *$/ {print ""; next} r {exit}' "$md")"
R="$(mktemp -d "${TMPDIR:-/tmp}/scout-run.XXXXXX")"
[ -n "${KEEP:-}" ] || trap 'rm -rf "$G" "$R"' EXIT
mkdir -p "$R/bin"
cat > "$R/bin/docker" <<'STUB'
#!/usr/bin/env bash
# build: read the Dockerfile, fail if asked. run: map -v SRC:DST, keep -e, run the command.
printf '%s\n' "$*" >> "$STUB_LOG"
if [ "$1" = build ]; then cat > /dev/null; [ -z "${STUB_BUILD_FAILS:-}" ]; exit; fi
shift; src=""; dst=""; envs=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -v) src="${2%%:*}"; rest="${2#*:}"; dst="${rest%%:*}"; shift 2 ;;
    -e) envs+=("$2"); shift 2 ;;
    -u|-w|--network|--tmpfs|--pids-limit|--memory) shift 2 ;;
    --rm|--read-only) shift ;;
    scout-props) shift; break ;;
    *) shift ;;
  esac
done
# The time limit is the container's own timeout (asserted from the log below); not every
# runner has timeout(1), so the stub drops it.
[ "${1:-}" = timeout ] && shift 2
args=(); for a in "$@"; do args+=("${a/#$dst/$src}"); done
[ "${args[0]:-}" = python ] && args[0]=python3
exec env "${envs[@]/#HOME=*/HOME=$HOME}" "${args[@]}"
STUB
chmod +x "$R/bin/docker"
(
  cd "$R" && git init -q -b main up && cd up && mkdir properties && printf 'x\n' > properties/old.py
  git add -A && git -c user.name=t -c user.email=t@t commit -qm base && cd .. && git clone -q up ws
) >/dev/null 2>&1
head_sha="$(git -C "$R/up" rev-parse HEAD)"
case_patch() {  # NAME, then files as path=content -> $R/NAME/aw-1.patch from a commit on head
  local name="$1"; shift; mkdir -p "$R/$name" "$R/rt-$name"
  (cd "$R/up" && git checkout -q -B "$name" "$head_sha" &&
   for kv in "$@"; do printf '%b' "${kv#*=}" > "${kv%%=*}"; done && git add -A &&
   git -c user.name=t -c user.email=t@t commit -qm "$name" &&
   git format-patch -q -1 --stdout > "$R/$name/aw-1.patch"; git checkout -q --detach "$head_sha") >/dev/null 2>&1
}
holds='print("p: properties held")\n'
fails='import sys\nsys.exit("AssertionError: counterexample")\n'
quiet='print("ran")\n'
heldfail='print("p: properties held")\nraise SystemExit(1)\n'
nothold='print("p: properties not held")\n'
case_patch good  "properties/good.py=$holds"
case_patch bad   "properties/bad.py=$fails"
case_patch quiet "properties/quiet.py=$quiet"
case_patch mixed "properties/a.py=$holds" "properties/b.py=$fails"
case_patch heldfail "properties/hf.py=$heldfail"
case_patch nothold  "properties/nh.py=$nothold"
case_patch editonly "properties/old.py=changed\n"
case_patch other    "bin/new.py=$holds"
mkdir -p "$R/none" "$R/rt-none" "$R/broken" "$R/rt-broken"
printf 'From 0 Mon Sep 17 00:00:00 2001\nSubject: x\n\n---\n garbage\n' > "$R/broken/aw-1.patch"
step_on() {  # NAME [build-fails] -> exit code of the step with that case's patch dir as /tmp/gh-aw
  printf '%s\n' "$runstep" | sed "s|/tmp/gh-aw/|$R/$1/|g" > "$R/step.sh"; : > "$R/docker.log"
  (cd "$R" && PATH="$R/bin:$PATH" STUB_LOG="$R/docker.log" GITHUB_WORKSPACE="$R/ws" HEAD_SHA="$head_sha" \
    RUNNER_TEMP="$R/rt-$1" STUB_BUILD_FAILS="${2:-}" bash --noprofile --norc -e -o pipefail "$R/step.sh") >"$R/$1.out" 2>&1
}
it "the run step was found in the workflow"; [ -n "$runstep" ] && ok || bad "no run step"
it "a new property that holds passes, and so does a run with no patch"
step_on good && ok || bad "refused a holding property: $(tail -5 "$R/good.out")"
step_on none && ok || bad "refused no patch"
grep -qF 'no patch: nothing to run' "$R/none.out" && ok || bad "no patch did not stop early: $(cat "$R/none.out")"
assert_none() { [ ! -s "$R/docker.log" ] && ok || bad "docker was used: $(cat "$R/docker.log")"; }
assert_none
it "a patch with no new property file (an edit, or a file outside properties/) runs nothing"
step_on editonly && ok || bad "an edit-only patch was refused: $(cat "$R/editonly.out")"
grep -qF 'no new property files' "$R/editonly.out" && ok || bad "did not stop early"; assert_none
step_on other && ok || bad "a non-property file was refused"; assert_none
it "a property that fails, or that exits 0 without saying it held, blocks the push"
step_on bad && bad "a failing property passed" || ok
step_on quiet && bad "a property that never said it held passed" || ok
it "the exit code and the exact held line are each required"
step_on heldfail && bad "a property that said held but exited 1 passed" || ok
step_on nothold && bad "'properties not held' passed" || ok
it "every new property runs, and one failing among several blocks the push and is named"
step_on mixed && bad "mixed passed" || ok
grep -qF '== properties/b.py' "$R/mixed.out" && ok || bad "stopped before the second file: $(cat "$R/mixed.out")"
grep -qF '::error file=properties/b.py::' "$R/mixed.out" && ok || bad "the failing file is not named"
it "the same patch in /tmp/gh-aw and gh-aw's threat-detection copy is applied once (#68)"
mkdir -p "$R/dup/threat-detection" "$R/rt-dup" && cp "$R/good/aw-1.patch" "$R/dup/" && cp "$R/good/aw-1.patch" "$R/dup/threat-detection/"
step_on dup && ok || bad "the copied patch was refused: $(tail -5 "$R/dup.out")"
runs="$(grep -c '^run ' "$R/docker.log")"; [ "$runs" = 1 ] && ok || bad "the property ran $runs times"
it "a patch that does not apply, or an image that does not build, blocks the push"
step_on broken && bad "a broken patch passed" || ok
cp -r "$R/good" "$R/good2"; mkdir -p "$R/rt-good2"; step_on good2 fail && bad "a failed image build passed" || ok
it "the properties run with no network, a read-only source, a time limit and a pinned image"
step_on good
grep -q -- '--network none' "$R/docker.log" && ok || bad "no --network none: $(cat "$R/docker.log")"
grep -q -- '--read-only' "$R/docker.log" && ok || bad "not read-only"
grep -q -- ':/w:ro' "$R/docker.log" && ok || bad "source not mounted read-only"
grep -q -- 'scout-props timeout 300 python -I' "$R/docker.log" && ok || bad "no time limit"
for flag in '-u ' '--tmpfs /tmp' '--tmpfs /home/scout' '--pids-limit 512' '--memory 2g' '-e HOME=/home/scout' '--rm'; do
  grep -qF -- "$flag" "$R/docker.log" && ok || bad "missing $flag"
done
printf '%s' "$runstep" | grep -qE 'FROM python:3\.12-slim@sha256:[0-9a-f]{64}' && ok || bad "image not pinned by digest"

it "this test runs in CI"
grep -qF 'bash bin/property-scout-workflow.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
