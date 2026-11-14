"""report.py FILE.jsonl... [--runs 5]: the table and the answer from the harness's lines.

Prints Markdown: a table per task and arm, with the mean and the range of each measure over
the runs that count, and then one sentence a measure by the rule of requirement R7 of record
docs/changes/2026-11-08-outcome-evals.md. A run counts when its agent status is ok. Exit 2
when the counted lines name more than one model, or there is nothing to report.

The rule. Better is higher for hidden tests, probes, mutation score and coverage, lower for
files outside the task and tests weakened. A task is decided on a measure only when both
arms have --runs counted runs with a value for it. An arm is then ahead when its mean is
better by more than the larger of the two arms' ranges. The skill is said to improve a
measure when the plugin arm is ahead on at least three decided tasks and behind on none.
Where the plugin arm is ahead on a task and its mean cost a run there is more than twice
the baseline's, the gain is called a trade-off. The two counts, assertions and flaky, are
reported as numbers only.
"""
import argparse
import json
import sys

RULED = (("hidden", "Hidden tests", True), ("probes", "Probes", True), ("mutation", "Mutation score", True),
         ("coverage", "Changed-line coverage", True), ("outside", "Files outside the task", False),
         ("weakened", "Tests weakened", False))
ARMS = ("plugin", "baseline")


def value(line, key):
    m = (line.get("measures") or {}).get(key) or {}
    v = m.get("value")
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def values(lines, key):
    return [v for v in (value(l, key) for l in lines) if v is not None]


def mean(xs):
    return sum(xs) / len(xs) if xs else None


def cell(xs, digits=2):
    if not xs:
        return "none"
    if len(xs) == 1 or min(xs) == max(xs):
        return f"{mean(xs):.{digits}f}"
    return f"{mean(xs):.{digits}f} ({min(xs):.{digits}f} to {max(xs):.{digits}f})"


def count_of(lines, key, sub=None):
    xs = []
    for l in lines:
        v = ((l.get("measures") or {}).get(key) or {}).get("value")
        v = v.get(sub) if sub and isinstance(v, dict) else v
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            xs.append(v)
    return f"{mean(xs):.1f}" if xs else "none"


def reds(lines):
    red = total = 0
    for l in lines:
        v = ((l.get("measures") or {}).get("red_check") or {}).get("value")
        if isinstance(v, dict):
            red += v.get("red", 0)
            total += sum(n for n in v.values() if isinstance(n, int))
    return f"{red} of {total}" if total else "none"


def decide(by_arm, key, higher, need):
    """ahead, behind, even or None (not decided) for the plugin arm on one task."""
    p, b = values(by_arm["plugin"], key), values(by_arm["baseline"], key)
    if len(p) < need or len(b) < need:
        return None
    spread = max(max(p) - min(p), max(b) - min(b))
    gain = (mean(p) - mean(b)) if higher else (mean(b) - mean(p))
    return "ahead" if gain > spread else "behind" if -gain > spread else "even"


def main(argv):
    ap = argparse.ArgumentParser(prog="report.py")
    ap.add_argument("files", nargs="+")
    ap.add_argument("--runs", type=int, default=5)
    o = ap.parse_args(argv)
    lines = []
    for path in o.files:
        for raw in open(path, encoding="utf-8"):
            if raw.strip():
                lines.append(json.loads(raw))
    counted = [l for l in lines if (l.get("agent") or {}).get("status") == "ok"]
    models = sorted({l.get("model") for l in counted if l.get("model")})
    if len(models) > 1:
        print(f"report: the lines name more than one model ({', '.join(models)}); no table", file=sys.stderr)
        return 2
    if not lines:
        print("report: no lines", file=sys.stderr)
        return 2
    tasks = list(dict.fromkeys(l["task"] for l in lines))
    print(f"Model: {models[0] if models else 'none reported'}. {len(counted)} of {len(lines)} runs count; "
          f"a run that was cut off, saw a check or had the skill in the wrong arm does not.\n")
    by = {t: {a: [l for l in counted if l["task"] == t and l["arm"] == a] for a in ARMS} for t in tasks}
    for t in tasks:
        print(f"### {t}\n")
        print("| Arm | Runs | Hidden tests | Probes | Mutation | Coverage | Red tests | Outside | Weakened | Tests with no assertion | Weak assertions | Flaky | Lines added | Turns | Cost |")
        print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for a in ARMS:
            ls = by[t][a]
            started = len([l for l in lines if l["task"] == t and l["arm"] == a])
            turns = [l["turns"] for l in ls if isinstance(l.get("turns"), (int, float))]
            cost = [l["cost"] for l in ls if isinstance(l.get("cost"), (int, float))]
            print(f"| {a} | {len(ls)} of {started} | " + " | ".join(
                [cell(values(ls, k)) for k in ("hidden", "probes", "mutation", "coverage")]
                + [reds(ls), count_of(ls, "outside"), count_of(ls, "weakened"), count_of(ls, "assertions", "no_assertion"),
                   count_of(ls, "assertions", "weak"), count_of(ls, "flaky"), count_of(ls, "added"),
                   f"{mean(turns):.1f}" if turns else "none", f"{mean(cost):.2f}" if cost else "none"]) + " |")
        print()
    print("### What the numbers show\n")
    for key, name, higher in RULED:
        verdicts = {t: decide(by[t], key, higher, o.runs) for t in tasks}
        decided = [t for t in tasks if verdicts[t] is not None]
        ahead = [t for t in decided if verdicts[t] == "ahead"]
        behind = [t for t in decided if verdicts[t] == "behind"]
        if len(ahead) >= 3 and not behind:
            s = f"- {name}: the skill improves it. The plugin arm is ahead on {len(ahead)} of {len(decided)} decided tasks and behind on none."
        else:
            s = (f"- {name}: no effect shown. The plugin arm is ahead on {len(ahead)} and behind on {len(behind)} of "
                 f"{len(decided)} decided tasks; {len(tasks) - len(decided)} of {len(tasks)} tasks were not decided.")
        dear = []
        for t in ahead:
            pc = mean([l["cost"] for l in by[t]["plugin"] if isinstance(l.get("cost"), (int, float))])
            bc = mean([l["cost"] for l in by[t]["baseline"] if isinstance(l.get("cost"), (int, float))])
            if pc is not None and bc is not None and pc > 2 * bc:
                dear.append(t)
        if dear:
            s += f" On {', '.join(dear)} the gain costs more than twice the baseline: a trade-off."
        print(s)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
