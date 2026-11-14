#!/usr/bin/env bash
# Tests for the outcome-evals harness and its reporter (record 2026-11-08-outcome-evals,
# requirements R2, R3, R4, R7, R8, R9). A fake `claude` stands first on PATH: it applies a
# canned patch in the scratch repository, commits, and prints the event stream the real one
# prints. Fake `mutmut` and `coverage` stand in for the two tools. No model is called and
# nothing is installed. Needs bash, git and python3.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$here/run.sh"; REPORT="$here/report.py"
REPO_ROOT="$(cd "$here" && git rev-parse --show-toplevel)"
# The real path, not a link to it: on macOS the temporary folder is /var/..., a link to /private/var/...,
# and git and python name the real one.
# a suite that cannot make its temporary folder must not go on: TMPROOT would be the folder it was started in
TMPROOT="$(mktemp -d)" && TMPROOT="$(cd "$TMPROOT" && pwd -P)" || { echo "cannot make a temporary folder" >&2; exit 1; }
trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq()  { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
has()  { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "missing [$2] in: $(printf '%s' "$1" | head -c 500)"; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && bad "unexpected [$2] in: $(printf '%s' "$1" | head -c 500)" || ok; }

# ---- the fakes -----------------------------------------------------------------------
BIN="$TMPROOT/bin"; mkdir -p "$BIN" "$TMPROOT/patches"
for t in names-file names-csv format-json repeat defect-whitespace; do mkdir -p "$TMPROOT/patches/$t"; cp "$here/checks/$t/"*.patch "$TMPROOT/patches/$t/"; done
printf '%s\n' "$REPO_ROOT" > "$TMPROOT/secret"   # what the searching agent looks for; never in a variable
cat > "$BIN/claude" <<'FAKE'
#!/usr/bin/env python3
"""A stand-in for claude -p. FAKE_MODE says what it does; see run.test.sh."""
import glob, json, os, re, subprocess, sys, time
args = sys.argv[1:]
prompt = sys.stdin.read()
plugin = args[args.index("--plugin-dir") + 1] if "--plugin-dir" in args else None
arm = "plugin" if plugin else "baseline"
mode = os.environ.get("FAKE_MODE_" + arm.upper()) or os.environ.get("FAKE_MODE", "ok")
log = os.environ["FAKE_LOG"]; os.makedirs(log, exist_ok=True)
n = len(os.listdir(log)) + 1
json.dump({"argv": args, "env": dict(os.environ), "cwd": os.getcwd(), "prompt": prompt, "arm": arm,
           "plugin_top": sorted(os.listdir(plugin)) if plugin else [],
           "plugin_files": sorted(os.path.relpath(os.path.join(r, f), plugin) for r, _, fs in os.walk(plugin) for f in fs) if plugin else []},
          open(os.path.join(log, f"{n:03d}-{arm}.json"), "w"))
def emit(e): print(json.dumps(e), flush=True)
def tool(name, inp): emit({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": name, "input": inp}]}})
def git(*a): subprocess.run(["git", "-c", "user.name=agent", "-c", "user.email=agent@example.com", *a], check=True, capture_output=True)
skills = ["change-record:change"] if plugin else []
if mode == "skillbase": skills = ["change"]
if mode == "noskill": skills = []
model = args[args.index("--model") + 1] if "--model" in args else "none"
emit({"type": "system", "subtype": "init", "model": os.environ.get("FAKE_MODEL", model), "skills": skills, "plugins": []})
if mode == "fail":
    sys.exit(1)
if mode == "slow":
    time.sleep(30)
if mode == "search":
    secret = open(os.environ["FAKE_SECRET"]).read().strip()
    found = []
    for start in [os.getcwd()] + ([plugin] if plugin else []):
        d = start
        while True:
            if os.path.exists(os.path.join(d, "outcome-evals")) or glob.glob(os.path.join(d, "*", "acceptance.py")) or glob.glob(os.path.join(d, "checks")):
                found.append("on the way up from " + start + ": " + d)
            if d == os.path.dirname(d): break
            d = os.path.dirname(d)
        for p in glob.glob(os.path.dirname(start) + "/**/acceptance.py", recursive=True) + glob.glob(start + "/**/*.patch", recursive=True):
            found.append("beside or below " + start + ": " + p)
    found += ["in a variable: " + k for k, v in os.environ.items() if secret in v and k != "FAKE_SECRET"]
    found += ["in an argument: " + a for a in args if secret in a]
    open(os.environ["FAKE_FOUND"], "a").write("".join(f + "\n" for f in found))
task = re.search(r"docs/changes/2026-11-14-([a-z-]+)\.md", prompt).group(1)
if plugin: tool("Skill", {"skill": "change-record:change"})
if mode == "peek": tool("Bash", {"command": "cat ../../checks/" + task + "/acceptance.py"})
if mode != "idle":
    which = os.environ.get("FAKE_PATCH_" + arm.upper(), "reference" if plugin else "naive")
    git("checkout", "-q", "-b", "work")
    git("apply", os.path.join(os.environ["FAKE_PATCHES"], task, which + ".patch"))
    if mode == "gutted":
        src = open("tests/test_greet.py").read()
        open("tests/test_greet.py", "w").write(src.replace('    def test_greets_by_name(self):\n        self.assertEqual(greet("Ada"), "Hello, Ada!")\n', "    pass\n"))
    if mode == "shaky":
        open("tests/test_greet.py", "a").write("""

class Shaky(unittest.TestCase):
    def test_flip(self):
        import os
        p = os.path.join(os.path.dirname(__file__), "flip")
        n = int(open(p).read()) if os.path.exists(p) else 0
        open(p, "w").write(str(n + 1))
        self.assertEqual(n % 2, 0)

    def test_weak(self):
        self.assertIsNotNone(greet)
        self.assertEqual(greet, greet)
""")
    if mode == "subprocess":
        open("tests/test_greet.py", "w").write("""import subprocess
import sys
import unittest


class Cli(unittest.TestCase):
    def test_the_program(self):
        r = subprocess.run([sys.executable, "greet.py", "Ada", "-n", "2"], capture_output=True, text=True)
        self.assertEqual((r.returncode, r.stdout), (0, "Hello, Ada!\\nHello, Ada!\\n"))
""")
    if mode == "messy":
        open("notes.txt", "w").write("scratch\n")
        open("README.md", "a").write("\n`-n COUNT` repeats the greeting.\n")
        src = open("tests/test_greet.py").read()
        open("tests/test_greet.py", "w").write(src.replace('        self.assertEqual(greet("Ada"), "Hello, Ada!")\n', "        pass\n"))
    tool("Bash", {"command": "python3 -m unittest discover -s tests -t . && git commit -am work"})
    git("add", "-A"); git("commit", "-q", "-m", "feat: " + task)
res = {"type": "result", "subtype": "success", "is_error": False, "num_turns": 7, "duration_ms": 1234,
       "total_cost_usd": float(os.environ.get("FAKE_COST", "0.25")), "result": "Change: docs/changes/x.md"}
if mode == "overbudget": res.update(subtype="error_max_budget_usd", is_error=True)
emit(res)
FAKE
cat > "$BIN/mutmut" <<'FAKE'
#!/usr/bin/env bash
# A stand-in for mutmut. `run` makes mutants/ as the real one does: the tests, and a greet.py
# in which a mutant is switched on by MUTANT_UNDER_TEST=<module>.<name>, the module being
# greet when a test imports it and __main__ when the program is run. Here a mutant that is
# on and is listed in FAKE_KILLABLE breaks the program; any other leaves it as it was.
# `results` prints the mutants' names from the file FAKE_MUTMUT names, none of them checked.
case "${1:-}" in
  run)
    mkdir -p mutants && cp -R tests mutants/tests || exit 1
    { printf 'import os as _os\nif _os.environ.get("MUTANT_UNDER_TEST", "") in [__name__ + "." + m for m in _os.environ.get("FAKE_KILLABLE", "").split(",") if m]:\n    raise SystemExit(3)\n'
      printf 'if _os.environ.get("MUTANT_UNDER_TEST", "") == __name__ + "." + _os.environ.get("FAKE_HANGS", "none"):\n    import time as _t\n    _t.sleep(90)\n'
      [ -n "${FAKE_MUTANTS_BROKEN:-}" ] && printf 'raise SystemExit(4)\n'
      cat greet.py; } > mutants/greet.py ;;
  results) [ -n "${FAKE_MUTMUT:-}" ] && cat "$FAKE_MUTMUT" || { echo "mutmut: no results" >&2; exit 1; } ;;
  *) exit 2 ;;
esac
FAKE
cat > "$BIN/coverage" <<'FAKE'
#!/usr/bin/env bash
# A stand-in for coverage: `run` does nothing, `json -o FILE` copies the file FAKE_COVERAGE names.
case "${1:-}" in
  run) printf '%s\n' "$*" >> "${FAKE_COVERAGE_LOG:-/dev/null}"; cat .coveragerc >> "${FAKE_COVERAGE_LOG:-/dev/null}" 2>/dev/null; exit 0 ;;
  combine) echo combine >> "${FAKE_COVERAGE_LOG:-/dev/null}"; exit 0 ;;
  json) [ -n "${FAKE_COVERAGE:-}" ] && cp "$FAKE_COVERAGE" "$3" || { echo "coverage: no data" >&2; exit 1; } ;;
  *) exit 2 ;;
esac
FAKE
chmod +x "$BIN/claude" "$BIN/mutmut" "$BIN/coverage"
printf '    greet.x_main__mutmut_1: not checked\n    greet.x_main__mutmut_2: not checked\n    greet.x_main__mutmut_3: not checked\n    greet.x_main__mutmut_4: not checked\n    greet.x_refuse__mutmut_1: not checked\n    greet.x_greet__mutmut_1: not checked\n' > "$TMPROOT/mutants"
printf '    greet.x_greet__mutmut_1: not checked\n    greet.x_greet__mutmut_2: not checked\n' > "$TMPROOT/mutants-none"
python3 -c 'import json,sys; json.dump({"files": {"greet.py": {"executed_lines": list(range(1, 200)), "missing_lines": []}}}, open(sys.argv[1], "w")); json.dump({"files": {"greet.py": {"executed_lines": [], "missing_lines": list(range(1, 200))}}}, open(sys.argv[2], "w"))' "$TMPROOT/cov-all" "$TMPROOT/cov-none"
export FAKE_PATCHES="$TMPROOT/patches" FAKE_SECRET="$TMPROOT/secret" FAKE_MUTMUT="$TMPROOT/mutants" FAKE_COVERAGE="$TMPROOT/cov-all"
# the three mutants of main that the agent's tests kill, when a test imports greet
export FAKE_KILLABLE="x_main__mutmut_1,x_main__mutmut_2,x_main__mutmut_3"
unset FAKE_MODE FAKE_MODE_PLUGIN FAKE_MODE_BASELINE FAKE_COST FAKE_MODEL OLDPWD

# harness NAME [ENV=VALUE...] -- ARGS: one run of the harness, started from inside this
# repository as an owner would. OUT (the lines) and LOG (what the fake claude saw) are set by h.
harness() {
  local name="$1"; shift; local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  rm -rf "$OUT" "$LOG"
  (cd "$here" && env ${envs[@]+"${envs[@]}"} FAKE_LOG="$LOG" PATH="$BIN:${EXTRA_PATH:+$EXTRA_PATH:}$PATH" "$RUN" --tools-bin "$BIN" --out "$OUT" "$@" 2>&1)
}
# h NAME ...: harness in this shell's name: sets OUT and LOG here, `out` to what it printed, returns its exit
h() { OUT="$TMPROOT/$1.jsonl"; LOG="$TMPROOT/$1.log"; out="$(harness "$@")"; }
# field FILE ARM EXPR: a Python expression over the line `l` of that arm (the first such line)
field() { python3 -c 'import json,sys
ls = [json.loads(x) for x in open(sys.argv[1])]
l = next(x for x in ls if x["arm"] == sys.argv[2]); m = l["measures"]
print(eval(sys.argv[3]))' "$1" "$2" "$3" 2>&1; }
seen() { python3 -c 'import json,sys,glob
d = json.load(open(sorted(glob.glob(sys.argv[1] + "/*-" + sys.argv[2] + ".json"))[0]))
print(eval(sys.argv[3]))' "$LOG" "$1" "$2" 2>&1; }

echo "one run of each arm: the line (R2)"
h main -- --tasks repeat --runs 1; rc=$?
it "the harness exits 0 and writes one line a run"
assert_eq "0 2" "$rc $(wc -l < "$OUT" | tr -d ' ')"
it "a line names its task, arm, run and the model of the session's init event"
assert_eq "repeat plugin 1 claude-sonnet-5-5" "$(field "$OUT" plugin 'l["task"], l["arm"], l["run"], l["model"]' | tr -d "(),'")"
it "it has the agent's turns, cost and duration from the result event, and the agent's own status"
assert_eq "(7, 0.25, 1234, 'ok', None)" "$(field "$OUT" plugin 'l["turns"], l["cost"], l["duration_ms"], l["agent"]["status"], l["agent"]["reason"]')"
it "it says whether the change skill was listed and whether the Skill tool was called, in each arm"
assert_eq "(True, True) (False, False)" "$(field "$OUT" plugin 'l["skill_listed"], l["skill_called"]') $(field "$OUT" baseline 'l["skill_listed"], l["skill_called"]')"
it "every measure has an entry with a status and a value"
assert_eq "added assertions coverage flaky hidden mutation outside probes red_check weakened" "$(field "$OUT" plugin '" ".join(sorted(m))')"
assert_eq "True" "$(field "$OUT" plugin 'all(set(v) >= {"status", "value"} for v in m.values())')"
it "hidden tests and probes are the fraction that pass: the reference patch all, the naive one no trap"
assert_eq "(1.0, 1.0) (1.0, 0.0)" "$(field "$OUT" plugin 'm["hidden"]["value"], m["probes"]["value"]') $(field "$OUT" baseline 'm["hidden"]["value"], m["probes"]["value"]')"
it "red-check ran on the agent's commits: the reference's changed test file is red on the base"
assert_eq "('pass', {'red': 1})" "$(field "$OUT" plugin 'm["red_check"]["status"], m["red_check"]["value"]')"
it "the mutation score is over the functions the agent changed: the five of main and refuse, three of them killed; greet's is left out"
assert_eq "('pass', 0.6)" "$(field "$OUT" plugin 'm["mutation"]["status"], m["mutation"]["value"]')"
has "$(field "$OUT" plugin 'm["mutation"]["why"]')" "3 of 5 mutants in main, refuse"
it "coverage is over the changed lines that can run"
assert_eq "('pass', 1.0)" "$(field "$OUT" plugin 'm["coverage"]["status"], m["coverage"]["value"]')"
it "scope: nothing outside the task, nothing weakened, the lines added counted"
assert_eq "(0, 0, True)" "$(field "$OUT" plugin 'm["outside"]["value"], m["weakened"]["value"], m["added"]["value"] > 20')"
it "the two counts are counts (R4): tests and their assertions, and runs that ended differently"
assert_eq "(3, 0, 0, 0)" "$(field "$OUT" plugin 'm["assertions"]["value"]["tests"], m["assertions"]["value"]["no_assertion"], m["assertions"]["value"]["weak"], m["flaky"]["value"]')"

echo "how the agent is run (R9, and the Decisions)"
it "both arms: a shell, no setting sources, the pinned model, a budget, the event stream"
for arm in plugin baseline; do
  a="$(seen $arm '"|".join(d["argv"])')"
  has "$a" "-p|--permission-mode|acceptEdits|--allowedTools|Bash|--setting-sources||--model|claude-sonnet-5-5|--max-budget-usd|1.0|--output-format|stream-json|--verbose"
done
it "only the plugin arm has --plugin-dir"
assert_eq "True False" "$(seen plugin '"--plugin-dir" in d["argv"]') $(seen baseline '"--plugin-dir" in d["argv"]')"
it "the prompt is the task's, on standard input, the same for both arms"
assert_eq "True True" "$(seen plugin 'd["prompt"] == open("'"$here"'/tasks/repeat/prompt.md").read()') $(seen baseline 'd["prompt"] == open("'"$here"'/tasks/repeat/prompt.md").read()')"
it "the plugin arm's folder is a copy with the skill, the rules and the tools, and nothing of the evals"
pf="$(seen plugin '"\n".join(d["plugin_files"])')"
assert_eq ".claude-plugin RULES.md bin skills templates" "$(seen plugin '" ".join(d["plugin_top"])')"
for f in skills/change/SKILL.md bin/record-check .claude-plugin/plugin.json; do has "$pf" "$f"; done
for f in outcome-evals acceptance .patch .test.sh; do lacks "$pf" "$f"; done
it "the copy is not in this repository, and the scratch repository is not either"
assert_eq "False False" "$(seen plugin 'd["argv"][d["argv"].index("--plugin-dir") + 1].startswith("'"$REPO_ROOT"'")') $(seen plugin 'd["cwd"].startswith("'"$REPO_ROOT"'")')"

it "the model on the line is the one the session reports, not the one that was asked for"
h othermodel FAKE_MODEL=some-other-model -- --tasks repeat --runs 1 --arms baseline
assert_eq "some-other-model" "$(field "$OUT" baseline 'l["model"]')"

echo "no agent can reach the checks (R8)"
h search FAKE_MODE=search FAKE_FOUND="$TMPROOT/found" -- --tasks names-file --runs 1
it "an agent that searches upward from its folder and from the plugin's, and through its variables and arguments, finds nothing"
assert_eq "" "$(cat "$TMPROOT/found" 2>/dev/null)"
it "both arms searched: the file is there and both runs counted"
[ -f "$TMPROOT/found" ] && ok || bad "the fake agent wrote no report"
assert_eq "ok ok" "$(field "$OUT" plugin 'l["agent"]["status"]') $(field "$OUT" baseline 'l["agent"]["status"]')"
it "a variable of the caller's that holds this repository's path, and a PATH entry inside it, do not reach the agent"
rm -f "$TMPROOT/found"; EXTRA_PATH="$REPO_ROOT/bin"
h leak FAKE_MODE=search FAKE_FOUND="$TMPROOT/found" LEAK="$REPO_ROOT/somewhere" OLDPWD="$TMPROOT/patches" -- --tasks names-file --runs 1 --arms baseline
unset EXTRA_PATH
assert_eq "" "$(cat "$TMPROOT/found" 2>/dev/null)"; [ -f "$TMPROOT/found" ] && ok || bad "the fake agent wrote no report"
assert_eq "False False" "$(seen baseline '"LEAK" in d["env"]') $(seen baseline '"'"$REPO_ROOT"'" in d["env"]["PATH"]')"
it "OLDPWD is dropped whatever it holds, since a link to this repository would not look like its path; PWD is the scratch repository"
assert_eq "True" "$(seen baseline '"OLDPWD" not in d["env"] and d["env"]["PWD"] == d["cwd"]')"
it "the PATH the agent gets still finds its tools"
assert_eq "True" "$(seen baseline '"'"$BIN"'" in d["env"]["PATH"]')"
h peek FAKE_MODE=peek -- --tasks repeat --runs 1 --arms baseline
it "a run in which a tool call names a check file has the agent status error, saw a check"
assert_eq "('error', 'saw a check')" "$(field "$OUT" baseline 'l["agent"]["status"], l["agent"]["reason"]')"

echo "the skill in the wrong arm (R9)"
h skillbase FAKE_MODE=skillbase -- --tasks repeat --runs 1 --arms baseline
it "a baseline run whose init event lists the change skill is an error"
assert_eq "('error', 'the skill was in the baseline arm')" "$(field "$OUT" baseline 'l["agent"]["status"], l["agent"]["reason"]')"
h noskill FAKE_MODE=noskill -- --tasks repeat --runs 1 --arms plugin
it "a plugin run in which the skill is not listed is an error"
assert_eq "('error', 'the skill was not in the plugin arm')" "$(field "$OUT" plugin 'l["agent"]["status"], l["agent"]["reason"]')"

echo "an agent that does not finish"
h fail FAKE_MODE=fail -- --tasks repeat --runs 1 --arms baseline
it "an agent that fails: error, failed; the measures still say what is there"
assert_eq "('error', 'failed', 'skip')" "$(field "$OUT" baseline 'l["agent"]["status"], l["agent"]["reason"], m["red_check"]["status"]')"
t=$SECONDS; h slow FAKE_MODE=slow -- --tasks repeat --runs 1 --arms baseline --run-timeout 1
it "an agent past --run-timeout is stopped: error, out of time"
assert_eq "('error', 'out of time')" "$(field "$OUT" baseline 'l["agent"]["status"], l["agent"]["reason"]')"
[ $((SECONDS - t)) -lt 25 ] && ok || bad "it waited $((SECONDS - t)) s"
h overbudget FAKE_MODE=overbudget -- --tasks repeat --runs 1 --arms baseline
it "an agent the CLI stopped at its budget: error, over budget"
assert_eq "('error', 'over budget')" "$(field "$OUT" baseline 'l["agent"]["status"], l["agent"]["reason"]')"

echo "a measure that could not run never reads as a pass"
h nomut FAKE_MUTMUT= FAKE_COVERAGE= -- --tasks repeat --runs 1 --arms plugin
it "mutmut that fails and coverage that writes no report: error, with no value"
assert_eq "('error', None) ('error', None)" "$(field "$OUT" plugin 'm["mutation"]["status"], m["mutation"]["value"]') $(field "$OUT" plugin 'm["coverage"]["status"], m["coverage"]["value"]')"
h unreached FAKE_MUTMUT="$TMPROOT/mutants-none" FAKE_COVERAGE="$TMPROOT/cov-none" -- --tasks repeat --runs 1 --arms plugin
it "no mutant in the functions the agent changed: skip, with no score; lines that ran in no test: a coverage of 0"
assert_eq "('skip', None) ('pass', 0.0)" "$(field "$OUT" plugin 'm["mutation"]["status"], m["mutation"]["value"]') $(field "$OUT" plugin 'm["coverage"]["status"], m["coverage"]["value"]')"
h nokill FAKE_KILLABLE= -- --tasks repeat --runs 1 --arms plugin
it "mutants that no test notices are a score of 0, not a skip: they were run"
assert_eq "('pass', 0.0)" "$(field "$OUT" plugin 'm["mutation"]["status"], m["mutation"]["value"]')"
h brokenmutants FAKE_MUTANTS_BROKEN=1 -- --tasks repeat --runs 1 --arms plugin
it "a suite that does not pass in the mutants' folder with no mutant on gives no score: error"
assert_eq "('error', None)" "$(field "$OUT" plugin 'm["mutation"]["status"], m["mutation"]["value"]')"
has "$(field "$OUT" plugin 'm["mutation"]["why"]')" "with no mutant"

t=$SECONDS; h hang FAKE_KILLABLE= FAKE_HANGS=x_main__mutmut_4 -- --tasks repeat --runs 1 --arms plugin
it "a mutant that makes the program wait for ever is stopped and counts as killed"
assert_eq "('pass', 0.2)" "$(field "$OUT" plugin 'm["mutation"]["status"], m["mutation"]["value"]')"
[ $((SECONDS - t)) -lt 60 ] && ok || bad "it waited $((SECONDS - t)) s"
h stale MUTANT_UNDER_TEST=greet.x_main__mutmut_1 -- --tasks repeat --runs 1 --arms plugin
it "a mutant named in the caller's own environment is not on when the suite is run with none"
assert_eq "('pass', 0.6)" "$(field "$OUT" plugin 'm["mutation"]["status"], m["mutation"]["value"]')"

echo "an agent whose tests run the program as a subprocess"
h subproc FAKE_MODE=subprocess FAKE_KILLABLE="x_main__mutmut_1" FAKE_COVERAGE_LOG="$TMPROOT/covlog" -- --tasks repeat --runs 1 --arms plugin
it "a mutant is switched on under the module name the program has when it is run, so a test that only runs the program kills it"
assert_eq "('pass', 0.2)" "$(field "$OUT" plugin 'm["mutation"]["status"], m["mutation"]["value"]')"
has "$(field "$OUT" plugin 'm["mutation"]["why"]')" "1 of 5 mutants"
it "coverage is told to follow the subprocesses the tests start, and their data is combined"
cl="$(cat "$TMPROOT/covlog" 2>/dev/null)"
has "$cl" "patch = subprocess"; has "$cl" "parallel = True"; has "$cl" "combine"
h idle FAKE_MODE=idle -- --tasks repeat --runs 1 --arms plugin
it "an agent that committed nothing: red-check, coverage and mutation skip; the hidden checks still run"
assert_eq "skip skip skip pass" "$(field "$OUT" plugin '" ".join(m[k]["status"] for k in ("red_check", "coverage", "mutation", "hidden"))')"
it "and neither tool is asked to measure what did not change"
assert_eq "greet.py did not change | the agent changed no function of greet.py" "$(field "$OUT" plugin 'm["coverage"]["why"] + " | " + m["mutation"]["why"]')"
h messy FAKE_MODE=messy -- --tasks repeat --runs 1 --arms plugin
it "a file outside the task and an assertion taken out are counted; the README, which the agent also changed, is inside the task"
assert_eq "(1, 'notes.txt', 1)" "$(field "$OUT" plugin 'm["outside"]["value"], m["outside"]["why"], m["weakened"]["value"]')"
it "and the test left with no assertion shows in the count"
assert_eq "1" "$(field "$OUT" plugin 'm["assertions"]["value"]["no_assertion"]')"

h gutted FAKE_MODE=gutted -- --tasks repeat --runs 1 --arms plugin
it "a test function deleted counts with the assertion line it held"
assert_eq "(2, '1 test functions deleted, 1 assertion lines removed')" "$(field "$OUT" plugin 'm["weakened"]["value"], m["weakened"]["why"]')"
h shaky FAKE_MODE=shaky -- --tasks repeat --runs 1 --arms plugin
it "a test that passes every other time: two of the four further runs end differently"
assert_eq "2" "$(field "$OUT" plugin 'm["flaky"]["value"]')"
it "assertIsNotNone and assertEqual(x, x) are counted as weak"
assert_eq "2" "$(field "$OUT" plugin 'm["assertions"]["value"]["weak"]')"

echo "the cost stop (C2)"
h stop FAKE_COST=0.25 -- --tasks repeat --runs 2 --max-cost 0.3; rc=$?
it "no run starts once the summed cost has passed --max-cost; the rest are written as not started, and the exit is 3"
assert_eq "3 4 ok ok error error" "$rc $(wc -l < "$OUT" | tr -d ' ') $(python3 -c 'import json,sys; print(" ".join(json.loads(l)["agent"]["status"] for l in open(sys.argv[1])))' "$OUT")"
has "$(tail -1 "$OUT")" "not started"
it "the arms of a run go one after the other, so a stop leaves them even"
assert_eq "plugin baseline plugin baseline" "$(python3 -c 'import json,sys; print(" ".join(json.loads(l)["arm"] for l in open(sys.argv[1])))' "$OUT")"

echo "usage"
it "an unknown task, an unknown arm and no claude on PATH are exit 2, and nothing is run"
h u1 -- --tasks nope; a=$?; h u2 -- --arms both; b=$?
out="$(cd "$here" && PATH="/usr/bin:/bin" "$RUN" --tools-bin "$BIN" --out "$TMPROOT/u3.jsonl" 2>&1)"; c=$?
assert_eq "2 2 2 no" "$a $b $c $([ -e "$TMPROOT/u1.jsonl" ] && echo yes || echo no)"
it "--keep keeps each scratch repository and its event stream"
h keep -- --tasks repeat --runs 1 --arms baseline --keep "$TMPROOT/kept"
[ -f "$TMPROOT/kept/repeat-baseline-1/events.jsonl" ] && [ -f "$TMPROOT/kept/repeat-baseline-1/repo/greet.py" ] && ok || bad "$(ls -R "$TMPROOT/kept" 2>&1 | head -5)"

echo "the reporter (R3, R4, R7)"
# lines NAME: write known lines. gen TASK ARM VALUE... gives five runs with those hidden-test values.
gen() { python3 - "$@" <<'PY'
import json, sys
import os
task, arm, cost = sys.argv[1], sys.argv[2], float(sys.argv[3])
outside = int(os.environ.get("GEN_OUTSIDE", "0"))
for n, v in enumerate(sys.argv[4:], 1):
    v = float(v)
    print(json.dumps({"task": task, "arm": arm, "run": n, "model": "m1", "turns": 10, "cost": cost, "agent": {"status": "ok", "reason": None},
                      "measures": {"hidden": {"status": "pass", "value": v}, "probes": {"status": "pass", "value": v},
                                   "mutation": {"status": "skip", "value": None}, "coverage": {"status": "pass", "value": 1.0},
                                   "outside": {"status": "pass", "value": outside}, "weakened": {"status": "pass", "value": 0},
                                   "added": {"status": "pass", "value": 30}, "flaky": {"status": "pass", "value": 0},
                                   "assertions": {"status": "pass", "value": {"tests": 3, "no_assertion": 1, "weak": 2}},
                                   "red_check": {"status": "pass", "value": {"red": 1}}}}))
PY
}
report() { python3 -B "$REPORT" "$@" 2>&1; }
W="$TMPROOT/win.jsonl"; : > "$W"
for t in a b c; do gen $t plugin 0.2 1 1 1 0.9 1 >> "$W"; gen $t baseline 0.2 0.5 0.6 0.5 0.5 0.6 >> "$W"; done
# d and e: the plugin arm's mean is the better one, by less than the baseline's range
for t in d e; do gen $t plugin 0.2 0.8 0.8 0.8 0.8 0.8 >> "$W"; gen $t baseline 0.2 0.7 0.7 0.8 0.8 0.8 >> "$W"; done
out="$(report "$W")"
it "a win: ahead on three decided tasks by more than the larger range, behind on none"
has "$out" "- Hidden tests: the skill improves it. The plugin arm is ahead on 3 of 5 decided tasks and behind on none."
it "a better mean that is within the range is not ahead"
lacks "$out" "ahead on 5"
it "a measure with no value in any run is not decided anywhere, and says so"
has "$out" "- Mutation score: no effect shown. The plugin arm is ahead on 0 and behind on 0 of 0 decided tasks; 5 of 5 tasks were not decided."
it "a tie on every task: no effect shown"
has "$out" "- Changed-line coverage: no effect shown. The plugin arm is ahead on 0 and behind on 0 of 5 decided tasks; 0 of 5 tasks were not decided."
it "the table has one row an arm with the mean and the range, and the two counts as numbers only"
has "$out" "| plugin | 5 of 5 | 0.98 (0.90 to 1.00) | 0.98 (0.90 to 1.00) | none | 1.00 | 5 of 5 | 0.0 | 0.0 | 1.0 | 2.0 | 0.0 | 30.0 | 10.0 | 0.20 |"
has "$out" "| baseline | 5 of 5 | 0.54 (0.50 to 0.60) |"
it "the model is named once"
has "$out" "Model: m1. 50 of 50 runs count"
L="$TMPROOT/lower.jsonl"; : > "$L"
for t in a b c; do gen $t plugin 0.2 1 1 1 1 1 >> "$L"; GEN_OUTSIDE=2 gen $t baseline 0.2 1 1 1 1 1 >> "$L"; done
it "for files outside the task fewer is better: the arm with none is ahead"
has "$(report "$L")" "- Files outside the task: the skill improves it. The plugin arm is ahead on 3 of 3 decided tasks and behind on none."
M="$TMPROOT/mixed.jsonl"; cp "$W" "$M"; gen f plugin 0.2 0.1 0.1 0.1 0.1 0.1 >> "$M"; gen f baseline 0.2 0.9 0.9 0.9 0.9 0.9 >> "$M"
it "ahead on three and behind on one: no effect shown"
has "$(report "$M")" "- Hidden tests: no effect shown. The plugin arm is ahead on 3 and behind on 1 of 6 decided tasks; 0 of 6 tasks were not decided."
D="$TMPROOT/dear.jsonl"; : > "$D"
for t in a b c; do gen $t plugin 0.9 1 1 1 1 1 >> "$D"; gen $t baseline 0.2 0.5 0.5 0.5 0.5 0.5 >> "$D"; done
it "a gain at more than twice the baseline's cost a run is called a trade-off, task by task"
has "$(report "$D")" "- Hidden tests: the skill improves it. The plugin arm is ahead on 3 of 3 decided tasks and behind on none. On a, b, c the gain costs more than twice the baseline: a trade-off."
S="$TMPROOT/short.jsonl"; : > "$S"
for t in a b; do gen $t plugin 0.2 1 1 1 1 1 >> "$S"; gen $t baseline 0.2 0.5 0.5 0.5 0.5 0.5 >> "$S"; done
gen c plugin 0.2 1 1 1 1 >> "$S"; gen c baseline 0.2 0.5 0.5 0.5 0.5 0.5 >> "$S"
it "a task whose cell is short of five runs is not decided, so two wins and a short cell are no effect shown"
has "$(report "$S")" "- Hidden tests: no effect shown. The plugin arm is ahead on 2 and behind on 0 of 2 decided tasks; 1 of 3 tasks were not decided."
it "--runs sets how many runs a cell needs"
has "$(report "$S" --runs 4)" "- Hidden tests: the skill improves it. The plugin arm is ahead on 3 of 3 decided tasks and behind on none."
E="$TMPROOT/err.jsonl"; cp "$S" "$E"; python3 -c 'import json,sys
l = json.loads(open(sys.argv[1]).readline()); l.update(task="c", arm="plugin", run=5); l["agent"] = {"status": "error", "reason": "saw a check"}; l["measures"]["hidden"]["value"] = 1.0
open(sys.argv[2], "a").write(json.dumps(l) + "\n")' "$S" "$E"
it "a run whose agent status is error does not fill a cell"
has "$(report "$E")" "1 of 3 tasks were not decided"
has "$(report "$E")" "| plugin | 4 of 5 |"
X="$TMPROOT/models.jsonl"; cp "$W" "$X"; gen z plugin 0.2 1 | sed 's/"m1"/"m2"/' >> "$X"
it "lines that name more than one model give no table"
out="$(report "$X")"; assert_eq 2 "$?"; has "$out" "more than one model"
it "no lines is exit 2"
: > "$TMPROOT/none.jsonl"; out="$(report "$TMPROOT/none.jsonl")"; assert_eq 2 "$?"

echo "the suites run in CI"
it "the workflow runs the self-test and this suite"
wf="$(cat "$REPO_ROOT/.github/workflows/test.yml")"
has "$wf" "plugins/change-record/outcome-evals/checks/selftest.sh"; has "$wf" "plugins/change-record/outcome-evals/run.test.sh"

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
