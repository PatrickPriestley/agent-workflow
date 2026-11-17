#!/usr/bin/env bash
# Tests for transcripts compare (record docs/changes/2026-11-17-compare-proposals.md): a proposed
# skill edit run against the skill as it is, through the eval cases of its step, and kept only if
# the step's graders pass more often with it and no case scores lower. A stand-in for `claude
# plugin eval` answers from the skill file of the plugin it is given and $FAKE_EVAL; it logs each
# call. Needs bash, git and python3.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$here/transcripts"
TMPROOT="$(mktemp -d)" && TMPROOT="$(cd "$TMPROOT" && pwd -P)" || { echo "cannot make a temporary folder" >&2; exit 1; }
trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()  { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 900)"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "unexpected [$2] in: $(printf '%s' "$1" | head -c 900)" || ok; }
py() { python3 "$@"; }
unset AGENT_TRANSCRIPTS AGENT_TRANSCRIPTS_URL
export AGENT_TRANSCRIPTS_PARENT=leak-check   # must not reach the eval runner

# ---- a repository with the plugin, and a folder of transcripts beside it -----------------------
REPO="$TMPROOT/repo"; P="$REPO/plugins/change-record"; mkdir -p "$P/skills/change" "$P/.claude-plugin" "$P/evals/results/old" "$P/evals/red-first"
printf '{"name": "change-record"}\n' > "$P/.claude-plugin/plugin.json"
printf 'a run of earlier days\n' > "$P/evals/results/old/run.json"
printf 'case\n' > "$P/evals/red-first/case.yaml"
USED="$(printf -- '---\nname: change\n---\n# Change\n\n1. Write the record.\n2. Write the code.\n3. Open the pull request.\n')"
printf '%s\n' "$USED" > "$P/skills/change/SKILL.md"
git -C "$REPO" init -q && git -C "$REPO" -c user.name=t -c user.email=t@example.com add -A && git -C "$REPO" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m skill
BLOB="$(git -C "$REPO" hash-object "$P/skills/change/SKILL.md")"
D="$TMPROOT/transcripts"; SID="11111111-2222-3333-4444-555555555555"
# proposal SID STEP: the edit `transcripts propose` would have drafted, against the file the session used
proposal() {
  local out="$D/proposals/$SID/$2"; mkdir -p "$out"
  py - "$here/../grade" "$out" "$USED" "$BLOB" "$1" "$2" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import propose
out, used, blob, sid, step = sys.argv[2:7]
used += "\n"
edited = used.replace("2. Write the code.\n", "2. Write a test, see it fail. EDITED\n3. Write the code.\n").replace("3. Open", "4. Open")
open(out + "/SKILL.md", "w").write(edited)
open(out + "/SKILL.diff", "w").write(propose.diff(used, edited, "change-record:change"))
json.dump({"session_id": sid, "step": step, "skill": "change-record:change", "skill_blob": blob, "eval": propose.cases(step)},
          open(out + "/proposal.json", "w"))
PY
}
proposal "$SID" red-first

# ---- a stand-in for the eval runner ------------------------------------------------------------
# FAKE_EVAL, JSON: {"current"|"edit": {"<case>": SPEC}}, the arm told by whether the plugin's skill
# says EDITED. SPEC is a list of runs, each {"<grader>": true|false}, or "error" (a run that
# errored), "partial", or "exit:N". It writes what the real runner writes with --json.
FAKEBIN="$TMPROOT/fakebin"; mkdir -p "$FAKEBIN"; FAKELOG="$TMPROOT/fake.log"; export FAKELOG
cat > "$FAKEBIN/claude" <<'PY'
#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
with open(os.environ["FAKELOG"], "a") as f:
    f.write(json.dumps({"argv": argv, "cwd": os.getcwd(),
                        "leak": [k for k in os.environ if k.startswith("AGENT_TRANSCRIPTS")]}) + "\n")
if argv[:2] != ["plugin", "eval"]:
    sys.exit(9)
plugin, case, out = argv[2], argv[argv.index("--case") + 1], argv[argv.index("--json") + 1]
arm = "edit" if "EDITED" in open(os.path.join(plugin, "skills", "change", "SKILL.md")).read() else "current"
spec = json.loads(os.environ["FAKE_EVAL"])[arm][case]
if spec == "nojson":
    sys.exit(0)
good = [{"saw-it-fail": True, ("test-run-before-code-change" if case == "red-first" else "test-run-before-workflow-change"): True}]
runs = [{"error": None, "costUsd": 0.1, "graders": [{"name": g.replace("unscored:", ""), "passed": v, "scored": not g.startswith("unscored:")}
                                                    for g, v in run.items()]}
        for run in (spec if isinstance(spec, list) else good)]
if spec == "error":
    runs[0]["error"] = "the agent timed out"
names = sorted({g["name"] for r in runs for g in r["graders"]})
graders = [{"name": n, "type": "tool_used", "config": {"tool": "Skill"}} if n == "skill-fired"
           else {"name": n, "type": "regex", "config": {}} for n in names]
json.dump({"partial": spec == "partial", "costUsd": 0.1 * len(runs),
           "cases": [{"name": case, "graders": graders, "arms": {"with": runs}}]}, open(out, "w"))
if isinstance(spec, str) and spec.startswith("exit:"):
    sys.exit(int(spec[5:]))
sys.exit(0 if all(all(g["passed"] for g in r["graders"]) for r in runs if not r["error"]) else 1)
PY
chmod +x "$FAKEBIN/claude"; export PATH="$FAKEBIN:$PATH"
calls() { [ -f "$FAKELOG" ] && wc -l < "$FAKELOG" | tr -d ' ' || echo 0; }
compare() { (cd "$REPO" && "$T" compare "$D" --session "$SID" "$@" 2>&1); }
# run GRADERS_PASSED_IN_ORDER: a run with the two red-first graders of a case and skill-fired
r() { printf '{"saw-it-fail": %s, "%s": %s, "skill-fired": %s}' "$1" "$2" "$3" "$4"; }
T1=test-run-before-code-change; T2=test-run-before-workflow-change

echo "transcripts compare"
it "with no session or no step, an unknown step, runs that are not a whole number above 0, or a ceiling that is no amount, it says how to use it"
out="$(cd "$REPO" && "$T" compare "$D" --step red-first 2>&1)"; assert_eq 2 "$?"; has "$out" "usage: transcripts compare"
out="$(compare)"; assert_eq 2 "$?"; has "$out" "usage: transcripts compare"
out="$(compare --step red-frist)"; assert_eq 2 "$?"; has "$out" "no such step 'red-frist'"
out="$(compare --step red-first --runs 0)"; assert_eq 2 "$?"; has "$out" "--runs"
out="$(compare --step red-first --max-cost x)"; assert_eq 2 "$?"; has "$out" "--max-cost"
out="$(compare --step red-first --again)"; assert_eq 2 "$?"; has "$out" "usage: transcripts compare"
it "a folder inside a working tree is refused, as for grade and propose"
out="$(cd "$REPO" && "$T" compare "$P" --session "$SID" --step red-first 2>&1)"; assert_eq 2 "$?"; has "$out" "inside the working tree"
it "a step with no proposal says so and runs nothing"
out="$(compare --step change-line)"; assert_eq 1 "$?"; has "$out" "no proposal for $SID at change-line"; assert_eq 0 "$(calls)"
it "a proposal whose skill or plugin name is a path, not one name, is refused: nothing outside the plugin is read or written"
VICTIM="$TMPROOT/victim"; mkdir -p "$VICTIM"; printf '%s\n' "$USED" > "$VICTIM/SKILL.md"
cp "$D/proposals/$SID/red-first/proposal.json" "$TMPROOT/proposal.keep"
for bad in "change-record:$VICTIM" "change-record:../../../victim" "/tmp:change" "change-record:" "change-record:.." "a/b:change"; do
  py -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["skill"]=sys.argv[2]; json.dump(d, open(p, "w"))' "$D/proposals/$SID/red-first/proposal.json" "$bad"
  : > "$FAKELOG"; out="$(compare --step red-first --run)"; assert_eq 1 "$?"; has "$out" "not one name"; assert_eq 0 "$(calls)"
done
it "a skill folder that is a link to somewhere outside the plugin is refused the same way"
ln -s "$VICTIM" "$P/skills/linked"
py -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["skill"]="change-record:linked"; json.dump(d, open(p, "w"))' "$D/proposals/$SID/red-first/proposal.json"
: > "$FAKELOG"; out="$(compare --step red-first --run)"; assert_eq 1 "$?"; has "$out" "not one name"; assert_eq 0 "$(calls)"
rm "$P/skills/linked"
assert_eq "$USED" "$(cat "$VICTIM/SKILL.md")"; assert_eq "no" "$([ -e "$D/compare" ] && echo yes || echo no)"
cp "$TMPROOT/proposal.keep" "$D/proposals/$SID/red-first/proposal.json"
it "a proposal naming a skill the plugin does not have says where it looked, and runs nothing"
py -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["skill"]="change-record:nosuch"; json.dump(d, open(p, "w"))' "$D/proposals/$SID/red-first/proposal.json"
: > "$FAKELOG"; out="$(compare --step red-first --run)"; assert_eq 1 "$?"; has "$out" "no skill file at $P/skills/nosuch/SKILL.md"; has "$out" "--repo-dir"; assert_eq 0 "$(calls)"
assert_eq "no" "$([ -e "$D/compare" ] && echo yes || echo no)"
cp "$TMPROOT/proposal.keep" "$D/proposals/$SID/red-first/proposal.json"
it "a session that is a path, not one id, is refused before anything is read, run or deleted"
ELSE="$TMPROOT/elsewhere"; mkdir -p "$ELSE/red-first"; cp "$D/proposals/$SID/red-first/"* "$ELSE/red-first/"; printf 'keep me\n' > "$ELSE/red-first/unrelated.txt"
for bad in "$ELSE" "../../elsewhere" "a/b" "." ".."; do
  : > "$FAKELOG"; out="$(cd "$REPO" && "$T" compare "$D" --session "$bad" --step red-first --run 2>&1)"; assert_eq 2 "$?"; has "$out" "not one session id"; assert_eq 0 "$(calls)"
done
assert_eq "keep me" "$(cat "$ELSE/red-first/unrelated.txt" 2>&1)"
it "a comparison folder that is a link to somewhere else is not deleted through"
export FAKE_EVAL="$(py -c 'import json,sys; g=json.loads(sys.argv[1]); print(json.dumps({"current": g, "edit": g}))' "$(py -c 'import json; print(json.dumps({"red-first": [{"saw-it-fail": True, "test-run-before-code-change": True}], "red-first-workflow": [{"saw-it-fail": True, "test-run-before-workflow-change": True}]}))')")"
rm -rf "$D/compare/$SID"; mkdir -p "$D/compare"; ln -s "$ELSE" "$D/compare/$SID"
: > "$FAKELOG"; out="$(compare --step red-first --run --runs 1)"; assert_eq 1 "$?"; has "$out" "is not inside"; assert_eq 0 "$(calls)"
assert_eq "keep me" "$(cat "$ELSE/red-first/unrelated.txt" 2>&1)"; rm "$D/compare/$SID"; rmdir "$D/compare"
it "a comparison root that is itself a link to somewhere else is not deleted through"
ROOT2="$TMPROOT/root2"; mkdir -p "$ROOT2/$SID/red-first"; printf 'keep me too\n' > "$ROOT2/$SID/red-first/unrelated.txt"
ln -s "$ROOT2" "$D/compare"
: > "$FAKELOG"; out="$(compare --step red-first --run --runs 1)"; assert_eq 1 "$?"; has "$out" "is not inside"; assert_eq 0 "$(calls)"
assert_eq "keep me too" "$(cat "$ROOT2/$SID/red-first/unrelated.txt" 2>&1)"; rm "$D/compare"
it "a step no eval case shows says that one is written first, and runs nothing"
proposal "$SID" record-check
out="$(compare --step record-check)"; assert_eq 1 "$?"; has "$out" "no eval case shows a failure of record-check"; assert_eq 0 "$(calls)"

it "without --run it says what it would run and the most it could spend, and runs nothing and writes nothing"
out="$(compare --step red-first)"; assert_eq 0 "$?"
has "$out" "red-first (graders saw-it-fail, $T1)"; has "$out" "red-first-workflow (graders saw-it-fail, $T2)"
has "$out" "6 runs with the skill as it is and 6 with the edit"; has "$out" "at most \$8.00"; has "$out" "--run"
has "$out" "the edit as drafted"
assert_eq 0 "$(calls)"; assert_eq "no" "$([ -e "$D/compare" ] && echo yes || echo no)"
assert_eq "no" "$([ -e "$D/proposals/$SID/red-first/compare.json" ] && echo yes || echo no)"
it "--runs and --max-cost change the plan's numbers"
out="$(compare --step red-first --runs 3 --max-cost 0.5)"; assert_eq 0 "$?"
has "$out" "3 runs with the skill as it is and 3 with the edit"; has "$out" "at most \$2.00"
out="$(compare --step red-first --runs 1)"; has "$out" "1 run with the skill as it is and 1 with the edit"; has "$out" "It would run"

it "with --run: the step's graders pass more often with the edit and no case scores lower, so the edit is kept"
export FAKE_EVAL="$(py - "$T1" "$T2" <<'PY'
import json, sys
t1, t2 = sys.argv[1:]
def runs(n, ok, t):
    return [{"saw-it-fail": i < ok, t: True, "skill-fired": True} for i in range(n)]
print(json.dumps({"current": {"red-first": runs(6, 3, t1), "red-first-workflow": runs(6, 4, t2)},
                  "edit": {"red-first": runs(6, 6, t1), "red-first-workflow": runs(6, 5, t2)}}))
PY
)"
: > "$FAKELOG"; out="$(compare --step red-first --run)"; rc=$?
assert_eq 0 "$rc"; has "$out" "keep"; has "$out" "19 of 24"; has "$out" "23 of 24"; has "$out" "It runs, with no arm"; lacks "$out" "It would run"
it "it ran each case once for each arm, with no arm without the plugin, at the runs and ceiling asked, and wrote the runner's results beside the proposal"
assert_eq 4 "$(calls)"
asked="$(py - "$FAKELOG" "$P" "$D/compare/$SID/red-first/plugin" <<'PY'
import json, sys
calls = [json.loads(l) for l in open(sys.argv[1])]
arms = {sys.argv[2]: "current", sys.argv[3]: "edit"}
def opt(a, k):
    return a[a.index(k) + 1] if k in a else None
for c in calls:
    a = c["argv"]
    print(arms.get(a[2], a[2]), opt(a, "--case"), opt(a, "--ablation"), opt(a, "--runs"), opt(a, "--max-cost-usd"),
          all(f in a for f in ("--scaffold", "--trust-plugin", "--no-publish")), "Bash" in a and "Write" in a and "Edit" in a,
          (opt(a, "--json") or "").startswith(sys.argv[3].rsplit("/", 1)[0]), c["leak"])
PY
)"
assert_eq "current red-first none 6 2 True True True []
edit red-first none 6 2 True True True []
current red-first-workflow none 6 2 True True True []
edit red-first-workflow none 6 2 True True True []" "$asked"
it "the edit's plugin is a copy that differs from the plugin only in the skill file, without the plugin's old results"
diffs="$(diff -r "$P" "$D/compare/$SID/red-first/plugin" 2>&1)"
has "$diffs" "Only in $P/evals: results"; has "$diffs" "skills/change/SKILL.md"
assert_eq 2 "$(printf '%s\n' "$diffs" | grep -c '^Only in\|^diff ')"
assert_eq "$(cat "$D/proposals/$SID/red-first/SKILL.md")" "$(cat "$D/compare/$SID/red-first/plugin/skills/change/SKILL.md")"
it "it never writes to the skill: the repository's file and tree are as they were"
assert_eq "$USED" "$(cat "$P/skills/change/SKILL.md")"; assert_eq "" "$(git -C "$REPO" status --porcelain)"
it "compare.json and compare.md hold the verdict and each case's counts for each arm"
cj="$D/proposals/$SID/red-first/compare.json"
assert_eq "keep 6 2.0 as drafted | red-first 3 6 12 0.75 1.0 | red-first-workflow 4 5 12 0.833 0.917" "$(py - "$cj" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d["verdict"], d["runs"], d["max_cost_usd"], d["applied"], "|", " | ".join(
    f'{c["case"]} {c["current"]["step_passed"] - 6} {c["edit"]["step_passed"] - 6} {c["current"]["step_total"]} '
    f'{round(c["current"]["mean"], 3)} {round(c["edit"]["mean"], 3)}' for c in d["cases"]))
PY
)"
has "$(cat "$D/proposals/$SID/red-first/compare.md")" "| red-first-workflow | 10 of 12 | 11 of 12 | 0.83 | 0.92 |"

it "a tie is no improvement: the edit is dropped"
export FAKE_EVAL="$(py -c '
import json
run = {"saw-it-fail": True, "test-run-before-code-change": False, "test-run-before-workflow-change": False, "skill-fired": True}
r1 = {k: v for k, v in run.items() if k != "test-run-before-workflow-change"}; r2 = {k: v for k, v in run.items() if k != "test-run-before-code-change"}
both = {"red-first": [r1] * 2, "red-first-workflow": [r2] * 2}
print(json.dumps({"current": both, "edit": both}))')"
out="$(compare --step red-first --run --runs 2)"; assert_eq 0 "$?"; has "$out" "drop"; has "$out" "not more often"
it "the step's graders pass more often, but a case scores lower on its other graders: dropped, naming the case"
export FAKE_EVAL="$(py -c '
import json
def run(s, t, o, k): return {"saw-it-fail": s, k: t, "other": o, "skill-fired": True}
k1, k2 = "test-run-before-code-change", "test-run-before-workflow-change"
print(json.dumps({"current": {"red-first": [run(False, True, True, k1)] * 2, "red-first-workflow": [run(True, True, True, k2)] * 2},
                  "edit": {"red-first": [run(True, True, True, k1)] * 2, "red-first-workflow": [run(True, True, False, k2)] * 2}}))')"
out="$(compare --step red-first --run --runs 2)"; assert_eq 0 "$?"; has "$out" "drop"; has "$out" "red-first-workflow scores lower"
it "skill-fired, the runner's sign that the skill was loaded, is not counted: it alone would have made the edit's case lower"
export FAKE_EVAL="$(py -c '
import json
def run(s, f, k): return {"saw-it-fail": s, k: True, "skill-fired": f}
k1, k2 = "test-run-before-code-change", "test-run-before-workflow-change"
# counted, skill-fired would make red-first 2/3 a run as it is and (2/3 + 1/3) / 2 with the edit: lower, so dropped
print(json.dumps({"current": {"red-first": [run(False, True, k1)] * 2, "red-first-workflow": [run(True, True, k2)] * 2},
                  "edit": {"red-first": [run(True, False, k1), {"saw-it-fail": False, k1: True, "skill-fired": False}],
                           "red-first-workflow": [run(True, True, k2)] * 2}}))')"
out="$(compare --step red-first --run --runs 2)"; assert_eq 0 "$?"; has "$out" "keep"

it "a run that errored, a result cut short by the ceiling, or a runner that exits otherwise gives no verdict, exit 1, and says which"
good="$(py -c 'import json; r={"saw-it-fail": True, "test-run-before-code-change": True}; w={"saw-it-fail": True, "test-run-before-workflow-change": True}; print(json.dumps({"red-first": [r], "red-first-workflow": [w]}))')"
for bad in error partial exit:2; do
  export FAKE_EVAL="$(py -c 'import json,sys; g=json.loads(sys.argv[1]); e=dict(g); e["red-first-workflow"]=sys.argv[2]; print(json.dumps({"current": g, "edit": e}))' "$good" "$bad")"
  out="$(compare --step red-first --run --runs 1)"; assert_eq 1 "$?"; has "$out" "no verdict"; has "$out" "red-first-workflow"
  assert_eq "none" "$(py -c 'import json,sys; print(json.load(open(sys.argv[1]))["verdict"])' "$cj")"
done
it "a run with no result for one of the step's graders gives no verdict, naming the grader"
export FAKE_EVAL="$(py -c 'import json,sys; g=json.loads(sys.argv[1]); e=dict(g); e["red-first"]=[{"saw-it-fail": True}]; print(json.dumps({"current": g, "edit": e}))' "$good")"
out="$(compare --step red-first --run --runs 1)"; assert_eq 1 "$?"; has "$out" "a run has no test-run-before-code-change"
it "an arm with fewer runs than were asked gives no verdict: raw counts of unequal runs are not compared"
export FAKE_EVAL="$(py -c '
import json, sys
g = json.loads(sys.argv[1]); e = json.loads(sys.argv[1])
g["red-first"] = [{"saw-it-fail": False, "test-run-before-code-change": True}]
e["red-first"] = [{"saw-it-fail": False, "test-run-before-code-change": True}] * 2
g["red-first-workflow"] = g["red-first-workflow"] * 2; e["red-first-workflow"] = e["red-first-workflow"] * 2
print(json.dumps({"current": g, "edit": e}))' "$good")"
out="$(compare --step red-first --run --runs 2)"; assert_eq 1 "$?"; has "$out" "no verdict"; has "$out" "red-first (current): 1 run of the 2 asked"
it "a grader the runner does not score is not counted: failing it alone would have made the edit's case lower"
export FAKE_EVAL="$(py -c '
import json, sys
g = json.loads(sys.argv[1]); e = json.loads(sys.argv[1])
g["red-first"] = [{"saw-it-fail": False, "test-run-before-code-change": True, "unscored:paid": True, "unscored:other": True}]
e["red-first"] = [{"saw-it-fail": True, "test-run-before-code-change": True, "unscored:paid": False, "unscored:other": False}]
# counted, they make red-first 3/4 as it is and 2/4 with the edit: lower, so dropped
print(json.dumps({"current": g, "edit": e}))' "$good")"
out="$(compare --step red-first --run --runs 1)"; assert_eq 0 "$?"; has "$out" "keep"
it "a runner that exits 0 and writes no result gives no verdict, even where an earlier run left one"
export FAKE_EVAL="$(py -c 'import json,sys; g=json.loads(sys.argv[1]); print(json.dumps({"current": g, "edit": g}))' "$good")"
compare --step red-first --run --runs 1 > /dev/null
export FAKE_EVAL="$(py -c 'import json,sys; g=json.loads(sys.argv[1]); e=dict(g); e["red-first"]="nojson"; print(json.dumps({"current": g, "edit": e}))' "$good")"
out="$(compare --step red-first --run --runs 1)"; assert_eq 1 "$?"; has "$out" "red-first (edit): no result"
it "no claude to run gives no verdict, never a traceback"
out="$(cd "$REPO" && PATH="/usr/bin:/bin" "$T" compare "$D" --session "$SID" --step red-first --run 2>&1)"; assert_eq 1 "$?"
has "$out" "no verdict"; lacks "$out" "Traceback"

it "a skill that changed since the session, away from the edit: the edit is put on the skill as it is now"
printf '%s\n\nA line added later.\n' "$USED" > "$P/skills/change/SKILL.md"
out="$(compare --step red-first)"; assert_eq 0 "$?"; has "$out" "the edit put on the skill as it is now"
export FAKE_EVAL="$(py -c 'import json,sys; g=json.loads(sys.argv[1]); print(json.dumps({"current": g, "edit": g}))' "$good")"
compare --step red-first --run --runs 1 > /dev/null
copy="$(cat "$D/compare/$SID/red-first/plugin/skills/change/SKILL.md")"
assert_eq "$(printf -- '---\nname: change\n---\n# Change\n\n1. Write the record.\n2. Write a test, see it fail. EDITED\n3. Write the code.\n4. Open the pull request.\n\nA line added later.')" "$copy"
it "a skill that changed where the edit goes: it says the edit must be made again by hand, and runs nothing"
printf -- '---\nname: change\n---\n# Change\n\n1. Write the record.\n2. Write the code, then its tests.\n3. Open the pull request.\n' > "$P/skills/change/SKILL.md"
: > "$FAKELOG"; out="$(compare --step red-first --run)"; assert_eq 1 "$?"; has "$out" "does not apply"; has "$out" "by hand"; assert_eq 0 "$(calls)"
it "a part of the edit that stands more than once in the skill as it is now: it is not guessed at, and nothing runs"
printf '%s\n\n%s\n' "$USED" "$USED" > "$P/skills/change/SKILL.md"   # the whole file twice: every part of the diff stands twice
: > "$FAKELOG"; out="$(compare --step red-first --run)"; assert_eq 1 "$?"; has "$out" "more than once"; assert_eq 0 "$(calls)"
it "an empty diff is no edit, and nothing runs"
printf '%s\n\nA line added later.\n' "$USED" > "$P/skills/change/SKILL.md"; : > "$D/proposals/$SID/red-first/SKILL.diff"
: > "$FAKELOG"; out="$(compare --step red-first --run)"; assert_eq 1 "$?"; has "$out" "holds no change"; assert_eq 0 "$(calls)"
git -C "$REPO" checkout -q -- .

echo
echo "transcripts compare: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
