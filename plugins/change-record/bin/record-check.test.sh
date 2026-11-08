#!/usr/bin/env bash
# Tests for record-check: real git repositories built in a scratch directory. Needs bash,
# git and python3 (the --json cases parse the document).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RC="$here/record-check"
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()  { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 600)"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "unexpected [$2] in: $(printf '%s' "$1" | head -c 600)" || ok; }

repo() {
  r="$TMPROOT/$1"; mkdir -p "$r/docs/changes"; cd "$r" || exit 1
  git init -q -b main; git config user.email t@example.com; git config user.name t
  git config core.hooksPath /dev/null
  printf 'hello\n' > lib.txt; printf '# Changes\n' > docs/changes/README.md
  git add -A; git commit -qm "feat: base"
  git checkout -qb feature
}
commit() { git add -A; git commit -qm "$1"; }
record() {  # PATH TIER STATUS [extra sections...]
  { printf -- '---\nid: %s\ntier: %s\nstatus: %s\nrequester: me\napprovers: []\n---\n# Title\n' "$(basename "$1" .md)" "$2" "$3"
    printf '## Goal\nx\n## Probed facts\nx\n## Decisions\nx\n## Tasks\nx\n## Checks\nx\n## Outcome\n'
    for s in "${@:4}"; do printf '## %s\nx\n' "$s"; done; } > "$1"
}
tier2() { record "$1" 2 "$2" "Problem" "Requirements" "Options and concerns"; }
body() { printf '%s\n' "$1" > "$TMPROOT/body.txt"; echo "$TMPROOT/body.txt"; }

it "a tier 1 record named in the PR body, with every section: pass, and the tier is printed"
repo t1; record docs/changes/2026-11-07-x.md 1 open; printf 'bye\n' >> lib.txt; commit "feat: x"
out="$(bash "$RC" --body "$(body 'Does x. Change: docs/changes/2026-11-07-x.md')" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "tier=1"; has "$out" "record=docs/changes/2026-11-07-x.md"

it "without a body, the one record changed in the range is used"
repo auto; record docs/changes/2026-11-07-y.md 1 open; printf 'bye\n' >> lib.txt; commit "feat: y"
out="$(bash "$RC" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "record=docs/changes/2026-11-07-y.md"

it "README.md and TEMPLATE.md under docs/changes are never taken for the record"
repo readme; printf 'more\n' >> docs/changes/README.md; printf '# T\n' > docs/changes/TEMPLATE.md; printf 'bye\n' >> lib.txt; commit "docs: readme"
out="$(bash "$RC" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "no change record"

it "no record and no tier 0 declaration: fail"
repo none; printf 'bye\n' >> lib.txt; commit "feat: z"
out="$(bash "$RC" --body "$(body 'just a change')" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "no change record"

it "a PR body that declares Tier: 0 passes without a record"
repo t0; printf 'helo -> hello\n' >> lib.txt; commit "docs: typo"
out="$(bash "$RC" --body "$(body $'Fix a typo.\n\nTier: 0')" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "tier=0"

it "a record named in the body but missing from the head: fail"
repo missing; printf 'bye\n' >> lib.txt; commit "feat: x"
out="$(bash "$RC" --body "$(body 'Change: docs/changes/2026-11-07-x.md')" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "not in the head commit"

it "frontmatter problems are named: no tier, a bad tier, a bad status, a mismatched id"
repo fm; printf 'bye\n' >> lib.txt
printf -- '---\nid: 2026-11-07-a\nstatus: open\n---\n# T\n' > docs/changes/2026-11-07-a.md; commit "feat: a"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "tier"
record docs/changes/2026-11-07-a.md 7 open; commit "feat: a2"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "tier must be 0, 1 or 2"
record docs/changes/2026-11-07-a.md 1 pending; commit "feat: a3"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "status must be"
record docs/changes/2026-11-07-a.md 1 open; sed -i.bak 's/^id: .*/id: other/' docs/changes/2026-11-07-a.md; rm -f docs/changes/2026-11-07-a.md.bak; commit "feat: a4"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "id must match the file name"

it "a missing section is named"
repo sections; printf 'bye\n' >> lib.txt
record docs/changes/2026-11-07-s.md 1 open; sed -i.bak '/^## Decisions/,/^## Tasks/{/^## Decisions/d;}' docs/changes/2026-11-07-s.md; rm -f docs/changes/2026-11-07-s.md.bak; commit "feat: s"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "missing section: Decisions"

it "a tier 2 record needs Problem, Requirements and Options and concerns"
repo t2sections; record docs/changes/2026-11-07-big.md 2 approved; commit "docs(change): big"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "missing section: Problem"

it "tier 2, the approval PR: only the record changes and status is approved: pass"
repo approval; tier2 docs/changes/2026-11-07-big.md approved; commit "docs(change): big"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 0 "$rc"; has "$out" "approval PR"

it "tier 2, a record still open alongside code: fail"
repo t2open; tier2 docs/changes/2026-11-07-big.md open; printf 'bye\n' >> lib.txt; commit "feat: big"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "approved before code"

it "tier 2, code with the record approved on the base: pass"
repo t2code; git checkout -q main; tier2 docs/changes/2026-11-07-big.md approved; commit "docs(change): big"
git checkout -q feature; git merge -q main; printf 'bye\n' >> lib.txt; commit "feat: big step 1"
out="$(bash "$RC" --body "$(body 'Change: docs/changes/2026-11-07-big.md')" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "tier=2"

it "tier 2, code and an approved record that is not on the base: fail"
repo t2unmerged; tier2 docs/changes/2026-11-07-big.md approved; printf 'bye\n' >> lib.txt; commit "feat: big with record"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "approved before code"

it "status done needs a filled Outcome section"
repo done; record docs/changes/2026-11-07-d.md 1 done; printf 'bye\n' >> lib.txt; commit "feat: d"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "Outcome is empty"
printf 'Shipped. Ran it: ok.\n' >> docs/changes/2026-11-07-d.md; commit "feat: d2"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 0 "$rc"

it "the mode is printed and written: approval for a record-only PR, code otherwise"
repo mode1; tier2 docs/changes/2026-11-07-big.md approved; commit "docs(change): big"
GITHUB_OUTPUT="$TMPROOT/mode.out"; : > "$GITHUB_OUTPUT"
out="$(GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$RC" --github 2>&1)"; has "$out" "mode=approval"; has "$(cat "$GITHUB_OUTPUT")" "mode=approval"
repo mode2; record docs/changes/2026-11-07-x.md 1 open; printf 'bye\n' >> lib.txt; commit "feat: x"
out="$(bash "$RC" 2>&1)"; has "$out" "mode=code"

it "tier 2 cannot be reached by raising a tier 1 record on the base alongside code"
repo upgrade; git checkout -q main; record docs/changes/2026-11-07-up.md 1 done; printf 'Shipped.\n' >> docs/changes/2026-11-07-up.md; commit "feat: tier 1 done"
git checkout -q feature; git merge -q main; tier2 docs/changes/2026-11-07-up.md approved; printf 'bye\n' >> lib.txt; commit "feat: sneaky"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "on the base commit"; has "$out" "tier 1"

it "a code PR cannot lower the tier of a record on the base; a record-only PR can"
repo lower; git checkout -q main; tier2 docs/changes/2026-11-07-dn.md approved; commit "docs(change): dn"
git checkout -q feature; git merge -q main; record docs/changes/2026-11-07-dn.md 1 open; printf 'bye\n' >> lib.txt; commit "feat: downgraded"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "lowered"
repo lower2; git checkout -q main; tier2 docs/changes/2026-11-07-dn.md approved; commit "docs(change): dn"
git checkout -q feature; git merge -q main; record docs/changes/2026-11-07-dn.md 1 open; commit "docs(change): dn is routine after all"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 0 "$rc"

it "--json prints one JSON document: status, tier, record, mode and the problems"
repo json1; record docs/changes/2026-11-07-j.md 1 open; printf 'bye\n' >> lib.txt; commit "feat: j"
out="$(bash "$RC" --json 2>/dev/null)"; rc=$?; assert_eq 0 "$rc"
assert_eq "record-check pass 1 docs/changes/2026-11-07-j.md code 0" "$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["check"],d["status"],d["tier"],d["record"],d["mode"],len(d["problems"]))')"
repo json2; printf 'bye\n' >> lib.txt; commit "feat: none"
out="$(bash "$RC" --json 2>/dev/null)"; rc=$?; assert_eq 1 "$rc"
assert_eq "fail 1 True" "$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["status"],len(d["problems"]),"no change record" in d["problems"][0])')"

it "--json on an approval PR is still one valid document"
repo json3; tier2 docs/changes/2026-11-07-big.md approved; commit "docs(change): big"
out="$(bash "$RC" --json 2>/dev/null)"; rc=$?; assert_eq 0 "$rc"
assert_eq "pass approval 2" "$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["status"],d["mode"],d["tier"])' 2>&1)"

it "a Change: line wins over an earlier mention of another record, and a longer path does not match"
repo choose; record docs/changes/2026-11-07-new.md 1 open; printf 'bye\n' >> lib.txt; commit "feat: new"
out="$(bash "$RC" --body "$(body $'Supersedes docs/changes/2026-09-01-old.md.\n\nChange: docs/changes/2026-11-07-new.md')" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "record=docs/changes/2026-11-07-new.md"
repo choose2; printf 'bye\n' >> lib.txt; commit "feat: no record"
out="$(bash "$RC" --body "$(body 'See apidocs/changes/2026-11-07-x.md and https://x.test/docs/changes/2026-11-07-y.md')" 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "no change record"
out="$(bash "$RC" --body "$(body 'Supersedes docs/changes/2026-09-01-old.md, see (docs/changes/2026-11-07-c.md).')" 2>&1)"
has "$out" "docs/changes/2026-09-01-old.md is named"   # no Change: line: the first boundary-anchored mention counts

it "a Change: line is recognised with the path in backticks, bold, or a markdown link"
repo fmt; record docs/changes/2026-11-07-new.md 1 open; printf 'bye\n' >> lib.txt; commit "feat: new"
for line in 'Change: `docs/changes/2026-11-07-new.md`' '**Change:** `docs/changes/2026-11-07-new.md`' 'Change: [the record](docs/changes/2026-11-07-new.md)'; do
  out="$(bash "$RC" --body "$(body "Supersedes docs/changes/2026-09-01-old.md.

$line")" 2>&1)"; has "$out" "record=docs/changes/2026-11-07-new.md"
done

it "a record with a non-ASCII slug is found from the Change: line and from the diff"
repo utf8; record docs/changes/2026-11-07-café.md 1 open; printf 'bye\n' >> lib.txt; commit "feat: café"
out="$(bash "$RC" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "record=docs/changes/2026-11-07-café.md"
# A second record in the range, so only the Change: line can pick the right one.
record docs/changes/2026-11-07-other.md 1 open; commit "docs(change): other"
out="$(bash "$RC" --body "$(body 'Change: docs/changes/2026-11-07-café.md')" 2>&1)"; rc=$?
assert_eq 0 "$rc"; has "$out" "record=docs/changes/2026-11-07-café.md"

it "--json stays valid when the tier is not a number"
repo badtier; record docs/changes/2026-11-07-t.md high open; printf 'bye\n' >> lib.txt; commit "feat: t"
out="$(bash "$RC" --json 2>/dev/null)"; rc=$?; assert_eq 1 "$rc"
assert_eq "fail high True" "$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["status"], d["tier"], any("tier must be" in p for p in d["problems"]))' 2>&1)"

it "a record path with a newline is refused and cannot forge a line in GITHUB_OUTPUT"
repo nlpath; printf 'bye\n' >> lib.txt
record "docs/changes/2026-11-07-x
tier=0
.md" 1 open; commit "feat: odd name"
GITHUB_OUTPUT="$TMPROOT/nl.out"; : > "$GITHUB_OUTPUT"
out="$(GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$RC" --github 2>&1)"; rc=$?
assert_eq 1 "$rc"; has "$out" "newline"
if grep -qx 'tier=0' "$GITHUB_OUTPUT"; then bad "a forged tier=0 line reached GITHUB_OUTPUT"; else ok; fi

it "a brand-new tier 2 record cannot be born done: the approval PR sets approved first"
repo borndone; tier2 docs/changes/2026-11-07-big.md done; sed -i.bak 's/^## Outcome$/## Outcome\nShipped./' docs/changes/2026-11-07-big.md; rm -f docs/changes/*.bak; commit "docs(change): big, done"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 1 "$rc"; has "$out" "approved before it is done"
repo thendone; git checkout -q main; tier2 docs/changes/2026-11-07-big.md approved; commit "docs(change): big approved"
git checkout -q feature; git merge -q main; tier2 docs/changes/2026-11-07-big.md done; sed -i.bak 's/^## Outcome$/## Outcome\nShipped./' docs/changes/2026-11-07-big.md; rm -f docs/changes/*.bak; commit "docs(change): big done"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 0 "$rc"

it "a record-only PR may abandon a tier 2 record, approved or still a draft"
repo abandon1; git checkout -q main; tier2 docs/changes/2026-11-07-big.md approved; commit "docs(change): big approved"
git checkout -q feature; git merge -q main; tier2 docs/changes/2026-11-07-big.md abandoned; sed -i.bak 's/^## Outcome$/## Outcome\nDropped: the vendor shipped it./' docs/changes/2026-11-07-big.md; rm -f docs/changes/*.bak; commit "docs(change): big abandoned"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 0 "$rc"; has "$out" "mode=approval"
repo abandon2; tier2 docs/changes/2026-11-07-big.md abandoned; commit "docs(change): never mind"
out="$(bash "$RC" 2>&1)"; rc=$?; assert_eq 0 "$rc"

it "--json and --github together are a usage error"
repo both; record docs/changes/2026-11-07-b.md 1 open; printf 'bye\n' >> lib.txt; commit "feat: b"
out="$(bash "$RC" --json --github 2>&1)"; rc=$?; assert_eq 2 "$rc"; has "$out" "--json and --github"

it "a record path with a newline cannot inject a workflow command into --github annotations"
repo inject; printf 'bye\n' >> lib.txt; commit "feat: x"
out="$(bash "$RC" --github --body "$(body $'Change: docs/changes/2026-11-07-missing.md')" 2>&1)"
has "$out" "::error::record-check: docs/changes/2026-11-07-missing.md is named"

it "--github writes tier and record to GITHUB_OUTPUT and an error annotation on failure"
repo gh; record docs/changes/2026-11-07-g.md 1 open; printf 'bye\n' >> lib.txt; commit "feat: g"
GITHUB_OUTPUT="$TMPROOT/gh.out"; : > "$GITHUB_OUTPUT"
GITHUB_OUTPUT="$GITHUB_OUTPUT" bash "$RC" --github >/dev/null 2>&1
has "$(cat "$GITHUB_OUTPUT")" "tier=1"; has "$(cat "$GITHUB_OUTPUT")" "record=docs/changes/2026-11-07-g.md"
repo gh2; printf 'bye\n' >> lib.txt; commit "feat: none"
out="$(bash "$RC" --github 2>&1)"; has "$out" "::error::"

it "usage errors: a bad range, an unknown option, a missing body file"
repo usage; printf 'bye\n' >> lib.txt; commit "feat: x"
out="$(bash "$RC" nope..HEAD 2>&1)"; rc=$?; assert_eq 2 "$rc"; has "$out" "unknown base"
out="$(bash "$RC" --bogus 2>&1)"; rc=$?; assert_eq 2 "$rc"
out="$(bash "$RC" --body /nonexistent 2>&1)"; rc=$?; assert_eq 2 "$rc"

printf 'passed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
