"""compare: a proposed skill edit run against the skill as it is, through the eval cases of its step.

Record docs/changes/2026-11-17-compare-proposals.md, and concern C5 of docs/changes/2026-11-12-session-quality.md:
an edit is kept only if the eval case that shows the failure improves with it, run with and without. This module
puts the edit on the skill as it is now, runs `claude plugin eval` for each arm, scores what the runner wrote and
gives the verdict. It never writes the skill: keeping an edit stays a change of its own.
"""
import subprocess

import judge

COMPARE = "compare/1"  # bump when the arms, the scoring or the rule changes
RUNS = 6               # runs of each arm of each case
CEILING = 2.0          # dollars each arm of each case may spend (the runner's --max-cost-usd)
TIMEOUT = 3600         # seconds one arm of one case may take


class NoFit(ValueError):
    """The edit cannot be put on the skill as it is now."""


def hunks(diff_text):
    """(old lines, new lines) of each hunk of a unified diff."""
    out, cur = [], None
    for line in diff_text.splitlines(keepends=True):
        if line.startswith("@@"):
            cur = ([], [])
            out.append(cur)
        elif cur is None or line.startswith("\\"):  # the file names before the first hunk; "\ No newline ..."
            continue
        elif line.startswith(" "):
            cur[0].append(line[1:])
            cur[1].append(line[1:])
        elif line.startswith("-"):
            cur[0].append(line[1:])
        elif line.startswith("+"):
            cur[1].append(line[1:])
    return out


def apply(current, diff_text):
    """The current skill with the edit put on it: each hunk must stand once, as it is, in the file."""
    lines = current.splitlines(keepends=True)
    parts = hunks(diff_text)
    if not parts:
        raise NoFit("the diff holds no change")
    for old, new in parts:
        at = [i for i in range(len(lines) - len(old) + 1) if old and lines[i:i + len(old)] == old]
        if len(at) != 1:
            where = next((s.strip() for s in old if s.strip()), "")[:80]
            raise NoFit(f"the part around {where!r} is {'not' if not at else 'more than once'} in it")
        lines[at[0]:at[0] + len(old)] = new
    return "".join(lines)


def command(plugin, case, runs, ceiling, out):
    """The runner's command for one arm of one case: the skill's own plugin, no arm without it."""
    return ["claude", "plugin", "eval", plugin, "--case", case, "--scaffold", "--allow-tools", "Bash", "Write", "Edit",
            "--trust-plugin", "--no-publish", "--ablation", "none", "--runs", str(runs), "-j", "4",
            "--max-cost-usd", f"{ceiling:g}", "--json", out]


def run_eval(plugin, case, runs, ceiling, out, cwd):
    """Run one arm of one case. None when it ran, else why there is no result to read."""
    try:  # the eval sessions are not captured: no AGENT_TRANSCRIPTS reaches them
        r = subprocess.run(command(plugin, case, runs, ceiling, out), capture_output=True, text=True,
                           timeout=TIMEOUT, cwd=cwd, env=judge.clean_env())
    except subprocess.TimeoutExpired:
        return f"no result in {TIMEOUT} s"
    except OSError as e:
        return f"claude did not start ({e})"
    if r.returncode not in (0, 1):  # 1: a run did not pass every grader; 2: the ceiling stopped it
        last = ((r.stderr or r.stdout or "").strip().splitlines() or [""])[-1][:200]
        return f"the eval runner exited {r.returncode}" + (f": {last}" if last else "")
    return None


def tally(result, case, step_graders, asked):
    """One arm of one case from the runner's --json: the step's graders passed, out of how many, and the mean over
    the runs of the share of scored graders passed. An arm with other than the runs asked has no result: the verdict
    compares counts, which mean the same only over the same number of runs. skill-fired, the runner's sign that the skill was loaded, is not
    counted: under --ablation none the runner scores it, and it measures the plugin, not the edit."""
    c = next((c for c in (result or {}).get("cases") or [] if isinstance(c, dict) and c.get("name") == case), None)
    if c is None:
        return {"problem": "no result"}
    if result.get("partial"):
        return {"problem": "the result was cut short (the ceiling, or the run was stopped)"}
    shown = {g.get("name") for g in c.get("graders") or []
             if g.get("type") == "tool_used" and (g.get("config") or {}).get("tool") == "Skill"}
    runs = (c.get("arms") or {}).get("with") or []
    if len(runs) != asked:
        return {"problem": f"{len(runs)} run{'' if len(runs) == 1 else 's'} of the {asked} asked"}
    passed = total = 0
    means = []
    for r in runs:
        if r.get("error"):
            return {"problem": f"a run errored ({str(r['error'])[:120]})"}
        scored = {g.get("name"): bool(g.get("passed")) for g in r.get("graders") or []
                  if g.get("scored") and g.get("name") not in shown}
        missing = [g for g in step_graders if g not in scored]
        if missing:
            return {"problem": f"a run has no {', '.join(missing)}"}
        passed += sum(scored[g] for g in step_graders)
        total += len(step_graders)
        means.append(sum(scored.values()) / len(scored))
    return {"step_passed": passed, "step_total": total, "mean": sum(means) / len(means), "runs": len(runs),
            "cost_usd": result.get("costUsd")}


def verdict(rows):
    """(keep | drop | none, why). Kept when the step's graders pass more often with the edit, over all its cases, and
    no case's mean is lower with it; a tie is dropped. No verdict when an arm has no result to read."""
    problems = [f"{r['case']} ({arm}): {r[arm]['problem']}" for r in rows for arm in ("current", "edit")
                if r[arm].get("problem")]
    if problems:
        return "none", "no verdict: " + "; ".join(problems)
    before = sum(r["current"]["step_passed"] for r in rows)
    after = sum(r["edit"]["step_passed"] for r in rows)
    total = sum(r["current"]["step_total"] for r in rows)
    lower = [r["case"] for r in rows if r["edit"]["mean"] < r["current"]["mean"] - 1e-9]
    counts = f"the step's graders passed {after} of {total} times with the edit and {before} of {total} without"
    if after <= before:
        return "drop", counts + ": not more often"
    if lower:
        return "drop", counts + f", but {' and '.join(lower)} scores lower with it on the case's other graders"
    return "keep", counts + ", and no case scores lower"


def plan(skill, sid, step, how, cases, runs, ceiling, evals_dir):
    """What `compare` would run, and the most it could spend."""
    lines = [f"transcripts compare: the edit to {skill} proposed from session {sid} at step {step}, the edit {how}.",
             "It would run, with no arm without the plugin:"]
    for case, graders in cases:
        lines.append(f"  {evals_dir}/{case} (grader{'s' if len(graders) > 1 else ''} {', '.join(graders)}): "
                     f"{runs} runs with the skill as it is and {runs} with the edit")
    lines.append(f"Each arm of each case stops at ${ceiling:.2f}, so at most ${2 * len(cases) * ceiling:.2f} in all.")
    return "\n".join(lines)


def page(skill, sid, step, how, runs, ceiling, rows, outcome, why):
    """compare.md: the verdict and each case's counts for each arm."""
    def cell(arm):
        return (f"{arm['step_passed']} of {arm['step_total']}", f"{arm['mean']:.2f}") if "problem" not in arm \
            else (f"no result: {arm['problem']}", "")
    out = [f"# Comparison of a proposed edit to {skill}", "",
           f"- Session: {sid}", f"- Step: `{step}`", f"- Edit: {how}",
           f"- Runs: {runs} an arm of each case, at most ${ceiling:.2f} an arm, no arm without the plugin ({COMPARE})",
           f"- Verdict: **{outcome}**: {why}", "",
           "| Case | Step's graders, the skill as it is | With the edit | Mean, as it is | Mean, with the edit |",
           "|---|---|---|---|---|"]
    for r in rows:
        (c1, m1), (c2, m2) = cell(r["current"]), cell(r["edit"])
        out.append(f"| {r['case']} | {c1} | {c2} | {m1} | {m2} |")
    out += ["", "The step's graders are those `propose.EVALS` names for the step. A mean is over the runs, of the share "
            "of the case's scored graders each run passed; `skill-fired` is not counted.", "",
            "The skill was not changed. An edit that is kept enters it as a change of its own, with its record.", ""]
    return "\n".join(out)
