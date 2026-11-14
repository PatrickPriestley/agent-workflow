"""The measures of one run (record docs/changes/2026-11-08-outcome-evals.md, requirement R2).

measure() looks at what an agent committed in a scratch repository and returns one entry a
measure: {"status", "value"} and, where it helps, "why". The status says what became of the
measuring, never whether the agent did well: pass (it ran and has a value), skip (there was
nothing to measure), error (it could not run), and for red-check its own pass, fail or warn.
How well the agent did is the value.

    hidden      fraction of the hidden acceptance tests that pass
    probes      fraction of the hidden probes that pass
    red_check   red-check's verdicts for the changed test files, as counts
    coverage    fraction of the changed, executable lines of greet.py the agent's tests run
    mutation    fraction of mutants killed, in the functions of greet.py the agent changed
    outside     files changed outside greet.py, README.md, tests/ and docs/changes/
    weakened    test functions deleted and assertion lines removed, against the base
    added       lines added
    assertions  a count: test functions, those with no assertion, weak assertions
    flaky       a count: of four more runs of the agent's suite, how many end differently

The scope measures read the agent's commits in the scratch repository. Everything that runs
code runs in a clone of it, so nothing a tool writes is taken for the agent's work.
"""
import ast
import json
import os
import re
import shutil
import subprocess
import tempfile

INSIDE = ("greet.py", "README.md")
INSIDE_DIRS = ("tests/", "docs/changes/")
UNCOUNTED = ("not checked", "skipped", "no tests")  # mutants no test was run against


def sh(cmd, cwd, env=None, timeout=300):
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)


def git(repo, *args):
    r = sh(["git", *args], repo)
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {r.stderr.strip()[:200]}")
    return r.stdout


def entry(status, value=None, why=None):
    e = {"status": status, "value": value}
    if why:
        e["why"] = why
    return e


def guarded(fn, *args):
    try:
        return fn(*args)
    except (OSError, RuntimeError, ValueError, SyntaxError, subprocess.SubprocessError) as e:
        return entry("error", None, f"{type(e).__name__}: {str(e)[:200]}")


# ---- what changed --------------------------------------------------------------------

def changed_lines(repo, base, path):
    """The line numbers of PATH at HEAD that the agent added or changed."""
    lines = set()
    for m in re.finditer(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@", git(repo, "diff", "-U0", base, "HEAD", "--", path), re.M):
        start, count = int(m.group(1)), int(m.group(2) or 1)
        lines.update(range(start, start + count))
    return lines


def changed_functions(source, lines):
    """The names of the functions whose text holds one of these lines."""
    names = set()
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and lines & set(range(node.lineno, node.end_lineno + 1)):
            names.add(node.name)
    return names


def test_functions(source):
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return set()
    return {n.name for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith("test")}


def scope(repo, base):
    """outside, weakened and added, from the agent's commits."""
    files = [f for f in git(repo, "diff", "--name-only", base, "HEAD").splitlines() if f]
    outside = sorted(f for f in files if f not in INSIDE and not f.startswith(INSIDE_DIRS))
    added = sum(int(l.split("\t")[0]) for l in git(repo, "diff", "--numstat", base, "HEAD").splitlines() if l.split("\t")[0].isdigit())
    deleted = 0
    for path in [f for f in git(repo, "ls-tree", "-r", "--name-only", base, "--", "tests").splitlines() if f.endswith(".py")]:
        before = test_functions(git(repo, "show", f"{base}:{path}"))
        now = sh(["git", "show", f"HEAD:{path}"], repo)
        deleted += len(before - (test_functions(now.stdout) if now.returncode == 0 else set()))
    diff = git(repo, "diff", "-U0", base, "HEAD", "--", "tests").splitlines()
    plus = {l[1:].strip() for l in diff if l.startswith("+") and not l.startswith("+++")}
    removed = sum(1 for l in diff if l.startswith("-") and not l.startswith("---") and "assert" in l and l[1:].strip() not in plus)
    return {"outside": entry("pass", len(outside), ", ".join(outside) or None),
            "weakened": entry("pass", deleted + removed, f"{deleted} test functions deleted, {removed} assertion lines removed" if deleted + removed else None),
            "added": entry("pass", added)}


# ---- the hidden checks ---------------------------------------------------------------

def hidden_checks(task, clone, checks_dir):
    r = sh(["bash", os.path.join(checks_dir, "run-checks.sh"), task, clone], clone)
    if r.returncode != 0:
        e = entry("error", None, (r.stderr.strip() or "run-checks.sh failed")[:200])
        return {"hidden": e, "probes": dict(e)}
    out = {}
    for key, where in (("hidden", "acceptance"), ("probes", "probe")):
        verdicts = [l.split()[3] for l in r.stdout.splitlines() if l.split()[:1] == [where] and len(l.split()) == 4]
        if not verdicts:
            out[key] = entry("error", None, f"run-checks.sh printed no {where} line")
            continue
        passed = verdicts.count("pass")
        out[key] = entry("pass", round(passed / len(verdicts), 3), f"{passed} of {len(verdicts)}")
    return out


# ---- red before green ----------------------------------------------------------------

def red_check(repo, base, tool):
    if git(repo, "rev-parse", "HEAD").strip() == base:
        return entry("skip", None, "the agent committed nothing")
    r = sh(["bash", tool, f"{base}..HEAD", "--run", "python3 -m unittest {files}", "--strict", "--json"], repo)
    try:
        doc = json.loads(r.stdout)
    except ValueError:
        return entry("error", None, (r.stderr.strip() or "red-check printed no JSON")[:200])
    counts = {}
    for f in doc.get("files") or []:
        counts[f.get("verdict")] = counts.get(f.get("verdict"), 0) + 1
    status = doc.get("status") if doc.get("status") in ("pass", "fail", "warn") else "error"
    return entry(status, counts, doc.get("summary"))


# ---- the agent's own tests -----------------------------------------------------------

SUITE = ["python3", "-B", "-m", "unittest", "discover", "-s", "tests", "-t", "."]


def flaky(clone):
    first = sh(SUITE, clone).returncode
    differing = sum(1 for _ in range(3) if sh(SUITE, clone).returncode != first)
    files = sorted((os.path.join("tests", f) for f in os.listdir(os.path.join(clone, "tests")) if f.startswith("test") and f.endswith(".py")), reverse=True)
    if files and sh(["python3", "-B", "-m", "unittest", *files], clone).returncode != first:
        differing += 1
    return entry("pass", differing, None if first == 0 else "the agent's suite fails")


def weak(call):
    name = call.func.attr if isinstance(call.func, ast.Attribute) else ""
    if name == "assertIsNotNone":
        return True
    if name == "assertTrue" and len(call.args) == 1 and isinstance(call.args[0], (ast.Name, ast.Attribute)):
        return True
    return name == "assertEqual" and len(call.args) >= 2 and ast.dump(call.args[0]) == ast.dump(call.args[1])


def assertions(clone):
    tests = bare = weak_ones = 0
    for root, _, names in os.walk(os.path.join(clone, "tests")):
        for n in names:
            if not n.endswith(".py"):
                continue
            tree = ast.parse(open(os.path.join(root, n), encoding="utf-8").read())
            for fn in ast.walk(tree):
                if not (isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)) and fn.name.startswith("test")):
                    continue
                tests += 1
                calls = [c for c in ast.walk(fn) if isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute) and c.func.attr.startswith("assert")]
                if not calls and not any(isinstance(s, ast.Assert) for s in ast.walk(fn)):
                    bare += 1
                weak_ones += sum(1 for c in calls if weak(c))
    return entry("pass", {"tests": tests, "no_assertion": bare, "weak": weak_ones})


def tool_env(tools_bin):
    return dict(os.environ, PATH=tools_bin + os.pathsep + os.environ.get("PATH", ""), PYTHONDONTWRITEBYTECODE="1")


def coverage(clone, lines, tools_bin):
    if not lines:
        return entry("skip", None, "greet.py did not change")
    env = tool_env(tools_bin)
    run = sh(["coverage", "run", "--source=.", "-m", "unittest", "discover", "-s", "tests", "-t", "."], clone, env)
    out = os.path.join(clone, ".coverage.json")
    rep = sh(["coverage", "json", "-o", out], clone, env)
    if rep.returncode != 0 or not os.path.exists(out):
        return entry("error", None, (rep.stderr.strip() or run.stderr.strip() or "coverage wrote no report")[-200:])
    f = (json.load(open(out)).get("files") or {}).get("greet.py") or {}
    ran, missed = set(f.get("executed_lines") or []), set(f.get("missing_lines") or [])
    could = lines & (ran | missed)
    if not could:
        return entry("skip", None, "no changed line of greet.py can be run")
    return entry("pass", round(len(could & ran) / len(could), 3), f"{len(could & ran)} of {len(could)} changed lines")


def mutation(clone, functions, tools_bin):
    if not functions:
        return entry("skip", None, "the agent changed no function of greet.py")
    env = tool_env(tools_bin)
    with open(os.path.join(clone, "setup.cfg"), "w") as f:
        f.write("[mutmut]\nsource_paths=greet.py\ntests_dir=tests\n")
    sh(["mutmut", "run"], clone, env, timeout=600)
    res = sh(["mutmut", "results", "--all", "true"], clone, env)
    if res.returncode != 0:
        return entry("error", None, (res.stderr.strip() or "mutmut results failed")[-200:])
    killed = counted = 0
    for m in re.finditer(r"^\s*(\S+?)__mutmut_\d+: (.+?)\s*$", res.stdout, re.M):
        fn = re.split(r"[.ǁ]", m.group(1))[-1]
        fn = fn[2:] if fn.startswith("x_") else fn
        if fn not in functions or m.group(2) in UNCOUNTED:
            continue
        counted += 1
        killed += m.group(2) == "killed"
    if not counted:
        return entry("skip", None, "no mutant in the changed functions was reached by a test")
    return entry("pass", round(killed / counted, 3), f"{killed} of {counted} mutants in {', '.join(sorted(functions))}")


def measure(task, repo, base, checks_dir, red_check_tool, tools_bin):
    out = {}
    scoped = guarded(scope, repo, base)
    out.update(scoped if "outside" in scoped else {k: dict(scoped) for k in ("outside", "weakened", "added")})
    out["red_check"] = guarded(red_check, repo, base, red_check_tool)
    holder = tempfile.mkdtemp(prefix="oe-measure-")
    try:
        clone = os.path.join(holder, "clone")
        try:
            git(repo, "clone", "-q", repo, clone)
            lines = changed_lines(repo, base, "greet.py")
            functions = changed_functions(open(os.path.join(clone, "greet.py"), encoding="utf-8").read(), lines) if lines else set()
        except (OSError, RuntimeError, SyntaxError) as e:
            bad = entry("error", None, f"{type(e).__name__}: {str(e)[:200]}")
            out.update({k: dict(bad) for k in ("hidden", "probes", "flaky", "assertions", "coverage", "mutation")})
            return out
        checks = guarded(hidden_checks, task, clone, checks_dir)
        out.update(checks if "hidden" in checks else {"hidden": checks, "probes": dict(checks)})
        out["flaky"] = guarded(flaky, clone)
        out["assertions"] = guarded(assertions, clone)
        out["coverage"] = guarded(coverage, clone, lines, tools_bin)
        out["mutation"] = guarded(mutation, clone, functions, tools_bin)
    finally:
        shutil.rmtree(holder, ignore_errors=True)
    return out
