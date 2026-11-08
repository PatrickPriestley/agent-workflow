#!/usr/bin/env bash
# scratch.sh DIR: build a scratch repository for probing record-check and red-check on a real
# GitHub Actions runner (.github/workflows/change-record-protocol.yml), or by hand.
#
#   main      lib.txt, run-tests.sh (a tiny runner: `bash run-tests.sh FILE...`), one green
#             test, docs/changes/README.md
#   code      a tier 1 record plus code and three test files: one red on main, one green on
#             main, one that cannot run on main (mode code)
#   approval  a tier 2 record with status approved and nothing else (mode approval)
#   tier0     a typo fix in README.md, no record (needs a `Tier: 0` body)
set -euo pipefail
dir="${1:?usage: scratch.sh DIR}"
mkdir -p "$dir"; cd "$dir"
git init -q -b main
git config user.email scratch@example.com; git config user.name scratch
mkdir -p tests docs/changes
cat > run-tests.sh <<'SH'
rc=0
check() { grep -qx "$1" lib.txt || { echo "FAIL: $1 missing"; rc=1; }; }
for f in "$@"; do . "./$f"; done
exit $rc
SH
printf 'hello\n' > lib.txt
printf 'check hello\n' > tests/test_hello.sh
printf '# Changes\n' > docs/changes/README.md
printf '# scratch\n\nA greating.\n' > README.md
git add -A; git commit -qm "feat: base"

record() {  # PATH TIER STATUS [extra sections...]
  { printf -- '---\nid: %s\ntier: %s\nstatus: %s\nrequester: probe\napprovers: []\n---\n# Probe\n' "$(basename "$1" .md)" "$2" "$3"
    printf '## Goal\nx\n## Probed facts\nx\n## Decisions\nx\n## Tasks\nx\n## Checks\nx\n## Outcome\n'
    for s in "${@:4}"; do printf '## %s\nx\n' "$s"; done; } > "$1"
}

git checkout -qb code
record docs/changes/2026-11-08-code.md 1 open
printf 'bye\n' >> lib.txt
printf 'check bye\n' > tests/test_red.sh                                  # red on main
printf 'check hello\n' > tests/test_green.sh                              # green on main
printf 'echo "ModuleNotFoundError: No module named x"; exit 1\n' > tests/test_broken.sh   # cannot run
git add -A; git commit -qm "feat: code with a record"

git checkout -q main; git checkout -qb approval
record docs/changes/2026-11-08-big.md 2 approved "Problem" "Requirements" "Options and concerns"
git add -A; git commit -qm "docs(change): big, approved"

git checkout -q main; git checkout -qb tier0
sed -i.bak 's/greating/greeting/' README.md; rm -f README.md.bak
git add -A; git commit -qm "docs: fix a typo"
git checkout -q main
echo "scratch repository at $dir: branches main, code, approval, tier0"
