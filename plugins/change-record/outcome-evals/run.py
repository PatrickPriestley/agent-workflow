"""The outcome-evals harness (record docs/changes/2026-11-08-outcome-evals.md). Use run.sh.

    run.sh [--tasks A,B] [--arms plugin,baseline] [--runs 5] [--model claude-sonnet-5-5]
           [--run-budget 1] [--run-timeout 600] [--max-cost 15] [--out FILE.jsonl]
           [--tools-bin DIR] [--keep DIR]

For each task, run and arm it builds the task's scaffold as a scratch repository in a
temporary folder of its own, runs the agent there on the task's prompt, then measures what
the agent committed and appends one JSON line to --out (default results/<time>.jsonl).

The agent is `claude -p --permission-mode acceptEdits --allowedTools Bash --setting-sources ""
--model M --max-budget-usd B --output-format stream-json --verbose`, with the prompt on
standard input. The plugin arm adds `--plugin-dir` with a copy of the plugin (its manifest,
skills, rules, bin and templates) made here, so that arm is never handed the folder the
checks live in. Neither arm loads anything installed for the user. The agent's working
folder is the scratch repository, and no variable or argument it gets holds this
repository's path.

A run's line has: task, arm, run, model, skill_listed, skill_called, turns, cost,
duration_ms, agent {status: ok|error, reason} and measures, each {status, value} with status
pass (it ran and has a value), fail, warn, skip (nothing to measure) or error (it could not
run). A run that was cut off, saw a check, or had the skill in the wrong arm has the agent
status error and is not counted by report.py.

Runs go task by task and run by run, the two arms of a run one after the other, so that a
stop leaves the arms even. No run starts once the summed cost has passed --max-cost; the
runs not started are written with the agent status error. Exit 0 when every run was
started, 3 when the cost stop cut the matrix short, 2 on a usage or setup problem.

--tools-bin DIR is put first on PATH for the measures and must hold `mutmut` and `coverage`
(and pytest, which mutmut runs the tests through). Without it the harness makes a virtual
environment in outcome-evals/.venv and installs the three there. --keep DIR keeps each
scratch repository and its event stream under DIR, for looking at afterwards.
"""
import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

import measures

HERE = os.path.dirname(os.path.realpath(__file__))
PLUGIN = os.path.dirname(HERE)
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or PLUGIN
TASKS = ("names-file", "names-csv", "format-json", "repeat", "defect-whitespace")
ARMS = ("plugin", "baseline")
PLUGIN_PARTS = (".claude-plugin", "skills", "RULES.md", "bin", "templates")
# a tool call whose input names any of these has looked at the checks
CHECK_WORDS = ("acceptance.py", "probes.sh", "naive.patch", "reference.patch", "outcome-evals", "run-checks")


def say(msg):
    print(f"outcome-evals: {msg}", file=sys.stderr, flush=True)


def plugin_copy(parent):
    """A copy of the plugin with nothing of the evals in it, for --plugin-dir."""
    dest = os.path.join(parent, "change-record")
    os.makedirs(dest)
    for part in PLUGIN_PARTS:
        src = os.path.join(PLUGIN, part)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(dest, part), ignore=shutil.ignore_patterns("__pycache__", "*.test.sh"))
        elif os.path.exists(src):
            shutil.copy2(src, os.path.join(dest, part))
    return dest


def agent_env(cwd):
    """The caller's environment without any trace of this repository's path."""
    env = {}
    for k, v in os.environ.items():
        if k in ("OLDPWD", "PWD") or REPO in v and k != "PATH":
            continue
        env[k] = os.pathsep.join(p for p in v.split(os.pathsep) if REPO not in p) if k == "PATH" else v
    env["PWD"] = cwd
    return env


def agent_command(arm, model, budget, copy):
    cmd = ["claude", "-p", "--permission-mode", "acceptEdits", "--allowedTools", "Bash", "--setting-sources", "",
           "--model", model, "--max-budget-usd", str(budget), "--output-format", "stream-json", "--verbose"]
    return cmd + (["--plugin-dir", copy] if arm == "plugin" else [])


def run_agent(cmd, prompt, cwd, timeout, stream_path):
    """(exit status or None when out of time). The event stream goes to stream_path."""
    with open(stream_path, "wb") as out:
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=out, stderr=subprocess.DEVNULL, cwd=cwd,
                             env=agent_env(cwd), start_new_session=True)
        try:
            p.communicate(prompt.encode(), timeout=timeout)
            return p.returncode
        except subprocess.TimeoutExpired:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            p.wait()
            return None


def read_stream(path):
    """What the agent's events say: model, whether the change skill was listed and called,
    whether a tool call named a check, and the result event (or None)."""
    seen = {"model": None, "skill_listed": False, "skill_called": False, "saw_check": False, "result": None}
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return seen
    for line in lines:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if not isinstance(e, dict):
            continue
        if e.get("type") == "system" and e.get("subtype") == "init":
            seen["model"] = e.get("model")
            seen["skill_listed"] = any(s == "change" or str(s).endswith(":change") for s in e.get("skills") or [])
        elif e.get("type") == "assistant":
            for c in (e.get("message") or {}).get("content") or []:
                if not (isinstance(c, dict) and c.get("type") == "tool_use"):
                    continue
                text = json.dumps(c.get("input"))
                if c.get("name") == "Skill" and "change" in text:
                    seen["skill_called"] = True
                if any(w in text for w in CHECK_WORDS):
                    seen["saw_check"] = True
        elif e.get("type") == "result":
            seen["result"] = e
    return seen


def agent_verdict(arm, rc, seen):
    """(status, reason) of the agent's own run."""
    res = seen["result"]
    if seen["saw_check"]:
        return "error", "saw a check"
    if arm == "baseline" and (seen["skill_listed"] or seen["skill_called"]):
        return "error", "the skill was in the baseline arm"
    if arm == "plugin" and not seen["skill_listed"]:
        return "error", "the skill was not in the plugin arm"
    if rc is None:
        return "error", "out of time"
    if res is not None and "budget" in str(res.get("subtype") or ""):
        return "error", "over budget"
    if rc != 0 or res is None or res.get("is_error"):
        return "error", "failed"
    return "ok", None


def one_run(task, arm, n, o, copy, tools_bin):
    scratch = tempfile.mkdtemp(prefix="oe-")
    repo = os.path.join(scratch, "repo")
    os.makedirs(repo)
    line = {"task": task, "arm": arm, "run": n, "model": None, "skill_listed": False, "skill_called": False,
            "turns": None, "cost": 0.0, "duration_ms": None, "agent": {"status": "error", "reason": "failed"}, "measures": {}}
    try:
        subprocess.run(["bash", os.path.join(HERE, "tasks", task, "scaffold.sh")], cwd=repo, check=True, capture_output=True)
        base = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, check=True, capture_output=True, text=True).stdout.strip()
        prompt = open(os.path.join(HERE, "tasks", task, "prompt.md"), encoding="utf-8").read()
        stream = os.path.join(scratch, "events.jsonl")
        t0 = time.time()
        rc = run_agent(agent_command(arm, o.model, o.run_budget, copy), prompt, repo, o.run_timeout, stream)
        seen = read_stream(stream)
        res = seen["result"] or {}
        status, reason = agent_verdict(arm, rc, seen)
        line.update(model=seen["model"], skill_listed=seen["skill_listed"], skill_called=seen["skill_called"],
                    turns=res.get("num_turns"), cost=float(res.get("total_cost_usd") or 0.0),
                    duration_ms=res.get("duration_ms") or int((time.time() - t0) * 1000),
                    agent={"status": status, "reason": reason})
        line["measures"] = measures.measure(task, repo, base, os.path.join(HERE, "checks"), os.path.join(PLUGIN, "bin", "red-check"), tools_bin)
    except (OSError, subprocess.CalledProcessError) as e:
        line["agent"] = {"status": "error", "reason": f"the harness could not run it: {e}"}
    finally:
        if o.keep:
            dest = os.path.join(o.keep, f"{task}-{arm}-{n}")
            shutil.rmtree(dest, ignore_errors=True)
            shutil.move(scratch, dest)
        else:
            shutil.rmtree(scratch, ignore_errors=True)
    return line


def tools(o):
    """The folder that holds mutmut and coverage: --tools-bin, or a virtual environment made here."""
    if o.tools_bin:
        return os.path.abspath(o.tools_bin)
    venv = os.path.join(HERE, ".venv")
    bin_dir = os.path.join(venv, "bin")
    if not (os.path.exists(os.path.join(bin_dir, "mutmut")) and os.path.exists(os.path.join(bin_dir, "coverage"))):
        say(f"making {venv} with pytest, mutmut and coverage")
        subprocess.run([sys.executable, "-m", "venv", venv], check=True)
        subprocess.run([os.path.join(bin_dir, "pip"), "install", "-q", "pytest", "mutmut", "coverage"], check=True)
    return bin_dir


def main(argv):
    p = argparse.ArgumentParser(prog="run.sh", add_help=True)
    p.add_argument("--tasks", default=",".join(TASKS))
    p.add_argument("--arms", default=",".join(ARMS))
    p.add_argument("--runs", type=int, default=5)
    p.add_argument("--model", default="claude-sonnet-5-5")
    p.add_argument("--run-budget", type=float, default=1.0)
    p.add_argument("--run-timeout", type=int, default=600)
    p.add_argument("--max-cost", type=float, default=15.0)
    p.add_argument("--out")
    p.add_argument("--tools-bin")
    p.add_argument("--keep")
    o = p.parse_args(argv)
    tasks, arms = [t for t in o.tasks.split(",") if t], [a for a in o.arms.split(",") if a]
    bad = [t for t in tasks if t not in TASKS] + [a for a in arms if a not in ARMS]
    if bad or not tasks or not arms or o.runs < 1:
        say(f"unknown task or arm: {', '.join(bad)}" if bad else "nothing to run")
        return 2
    if shutil.which("claude") is None:
        say("claude is not on PATH")
        return 2
    try:
        tools_bin = tools(o)
    except (OSError, subprocess.CalledProcessError) as e:
        say(f"cannot set up mutmut and coverage: {e}")
        return 2
    out = o.out or os.path.join(HERE, "results", time.strftime("%Y-%m-%dT%H%M%S") + ".jsonl")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    if o.keep:
        os.makedirs(o.keep, exist_ok=True)
    holder = tempfile.mkdtemp(prefix="oe-plugin-")
    spent, stopped = 0.0, False
    try:
        copy = plugin_copy(holder)
        with open(out, "a", encoding="utf-8") as f:
            for task in tasks:
                for n in range(1, o.runs + 1):
                    for arm in arms:
                        if spent >= o.max_cost:
                            stopped = True
                            line = {"task": task, "arm": arm, "run": n, "model": None, "cost": 0.0, "measures": {},
                                    "agent": {"status": "error", "reason": "not started: the total budget was spent"}}
                        else:
                            line = one_run(task, arm, n, o, copy, tools_bin)
                            spent += line["cost"]
                            say(f"{task} {arm} {n}: {line['agent']['status']}"
                                + (f" ({line['agent']['reason']})" if line["agent"]["reason"] else "")
                                + f", {line['cost']:.2f} dollars, {spent:.2f} in all")
                        f.write(json.dumps(line, sort_keys=True) + "\n")
                        f.flush()
    finally:
        shutil.rmtree(holder, ignore_errors=True)
    say(f"{out}: {spent:.2f} dollars" + ("; stopped at the total budget, the matrix is short" if stopped else ""))
    return 3 if stopped else 0


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    sys.exit(main(sys.argv[1:]))
