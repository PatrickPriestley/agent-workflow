"""The report over score rows (record docs/changes/2026-11-09-skill-transcripts.md, R11).

Rows are grouped by skill version, the skill's name and the git blob of its file, and two
versions are never counted together. Within a version each step is counted per grader, from the
latest row per session, step and grader. Proposed skill edits come only from steps whose latest
row for the session, whatever the grader, is a fail. The agreement between the Haiku judge and
the agreement judge is counted from the judge files of sessions both judged, on the same record.
"""
from datetime import datetime, timezone

import fields
import judge

ORDER = fields.STEPS + judge.QUESTIONS
EDITS = {
    "tier-declared": ('"1. Tier"', "make the tier the first thing written: `tier:` in the record's frontmatter, "
                      "or `Tier: 0` in the PR body for a change with no behaviour change."),
    "probe-before-record": ('"2. Probe, then record"', "say that the record is created only after a probe has run, "
                            "and name the probe to run first."),
    "record-before-code": ('"2. Probe, then record"', "say that no file outside docs/changes/ and the tests is "
                           "written until the record exists on the branch."),
    "red-first": ('"3. Loop", step 3 (Red, then green)', "require the failing test run's output to be seen before "
                  "the first code edit, and say that a denied or skipped test run does not count."),
    "change-line": ('"3. Loop", step 6 (Push)', "give the exact first line of the PR body to copy, "
                    "`Change: docs/changes/<id>.md`, with nothing before it."),
    "record-check": ('"2. Probe, then record"', "list the sections and frontmatter fields record-check requires, "
                     "so the record passes it before the PR opens."),
    "outcome-filled": ('"3. Loop", step 5 (Use it)', "say that a record is not done until its Outcome holds the "
                       "commands run and their output."),
    "decisions-alternative": ('"2. Probe, then record"', "ask for each Decision to name the alternative it rejected "
                              "and why, as `Rejected: <option>, because <reason>`."),
    "outcome-real-output": ('"3. Loop", step 5 (Use it)', "ask for the Outcome to quote the commands run and what "
                            "they printed, main path and one error path, not a summary or test counts."),
}
AGREEMENT_FLOOR = 80  # percent; below it C3 moves the default judge to the other family


def when(s):
    if not s:
        return None
    try:
        t = datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def step_key(step):
    return (ORDER.index(step), "") if step in ORDER else (len(ORDER), step)


def latest(rows, key):
    best = {}
    for r in rows:
        k = key(r)
        t = when(r.get("graded_at")) or datetime.min.replace(tzinfo=timezone.utc)
        if k not in best or t >= best[k][0]:
            best[k] = (t, r)
    return [r for _, r in best.values()]


def rate(p, f):
    return f"{round(100 * p / (p + f))}%" if p + f else "-"


def agreement(judges):
    by = {}
    for j in judges:
        k = (j.get("session_id"), j.get("kind"))
        if k not in by or (when(j.get("judged_at")) or datetime.min.replace(tzinfo=timezone.utc)) >= \
                (when(by[k].get("judged_at")) or datetime.min.replace(tzinfo=timezone.utc)):
            by[k] = j
    agree = total = sessions = paired = 0
    for (sid, kind), c in by.items():
        o = by.get((sid, "opencode"))
        if kind != "claude" or not o or o.get("judge") != c.get("judge") or o.get("record_sha256") != c.get("record_sha256"):
            continue
        paired += 1
        compared = 0
        for q, cq in (c.get("questions") or {}).items():
            oq = (o.get("questions") or {}).get(q) or {}
            if cq.get("votes") == [] or oq.get("votes") == []:
                continue  # decided without a judge (an empty section, a record not done): nothing to compare
            a, b = cq.get("verdict"), oq.get("verdict")
            if a in ("pass", "fail") and b in ("pass", "fail"):
                compared += 1
                agree += a == b
        total += compared
        sessions += compared > 0
    return agree, total, sessions, paired


def build(rows, entries, judges):
    rows = latest(rows, lambda r: (r["session_id"], r["step"], r["grader"]))
    if not rows:
        return None
    s_time = {}
    for r in rows:
        sid = r["session_id"]
        t = when((entries.get(sid) or {}).get("first_timestamp")) or when(r.get("graded_at"))
        if t and (sid not in s_time or t < s_time[sid]):
            s_time[sid] = t
    versions = {}
    for r in rows:
        versions.setdefault((r.get("skill") or "unknown", r.get("skill_blob")), []).append(r)
    far = datetime.max.replace(tzinfo=timezone.utc)

    def v_sessions(vr):
        return sorted({r["session_id"] for r in vr})

    def v_start(item):
        (skill, blob), vr = item
        return (min((s_time.get(s, far) for s in v_sessions(vr)), default=far), skill, blob or "")
    ordered = sorted(versions.items(), key=v_start)

    def label(skill, blob):
        return f"{skill}, blob {blob[:8] if blob else 'unknown'}"

    def day(t):
        return t.astimezone(timezone.utc).strftime("%Y-%m-%d") if t and t != far else "unknown"

    def counts(vr, step, grader):
        sel = [r for r in vr if r["step"] == step and r["grader"] == grader]
        return tuple(sum(r["verdict"] == v for r in sel) for v in ("pass", "fail", "not_applicable"))

    out = ["# Change skill report", "",
           f"Score rows from {len({r['session_id'] for r in rows})} sessions, grouped by skill version (the git blob of "
           "the skill file), oldest first; two versions are never counted together. A pass rate is pass / (pass + fail), "
           "with not applicable counted apart. Each step keeps the latest row per session and grader."]
    pairs_all = sorted({(r["step"], r["grader"]) for r in rows}, key=lambda p: (step_key(p[0]), p[1]))
    for (skill, blob), vr in ordered:
        ss = v_sessions(vr)
        times = [s_time[s] for s in ss if s in s_time]
        out += ["", f"## {label(skill, blob)}", "",
                f"Sessions: {len(ss)}, from {day(min(times) if times else None)} to {day(max(times) if times else None)}.", "",
                "| Step | Grader | Pass | Fail | N/A | Pass rate |", "|---|---|---|---|---|---|"]
        for step, grader in [p for p in pairs_all if any(r["step"] == p[0] and r["grader"] == p[1] for r in vr)]:
            p, f, n = counts(vr, step, grader)
            out.append(f"| {step} | {grader} | {p} | {f} | {n} | {rate(p, f)} |")

    out += ["", "## Pass rate over time", "",
            "Passes of graded sessions, per skill version, oldest first (the date is the version's first session).", ""]
    cols = [f"{blob[:8] if blob else 'unknown'} ({day(v_start(((s, blob), vr))[0])})" for (s, blob), vr in ordered]
    out += ["| Step | Grader | " + " | ".join(cols) + " |", "|---|---|" + "---|" * len(cols)]
    for step, grader in pairs_all:
        cells = []
        for _, vr in ordered:
            p, f, _ = counts(vr, step, grader)
            cells.append(f"{p} of {p + f}" if p + f else "-")
        out.append(f"| {step} | {grader} | " + " | ".join(cells) + " |")

    out += ["", "## Judge agreement", ""]
    a, n, s, paired = agreement(judges)
    other = judge.MODELS["opencode"]
    if n:
        pct = round(100 * a / n)
        line = f"The Haiku judge and {other} agree on {a} of {n} judgments ({pct}%), over {s} sessions judged by both."
        if pct < AGREEMENT_FLOOR:
            line += f" Below {AGREEMENT_FLOOR}%: per C3, the default judge should move to the other model family."
        out.append(line)
    elif paired:
        out.append(f"The agreement judge ran on {paired} sessions, but no question got a verdict from both judges: "
                   "their answers are in judges/*.opencode.json and judges/*.claude.json.")
    else:
        out.append(f"The agreement check has not run yet: no session here has been judged by both the Haiku judge and "
                   f"{other}. On the owner's machine, run `transcripts judge DIR --judge opencode`, then this report again.")

    out += ["", "## Proposed skill edits", "",
            "From failed sessions only, citing each session and step, per skill version, newest first."]
    final = latest(rows, lambda r: (r["session_id"], r["step"]))
    any_edit = False
    for (skill, blob), vr in reversed(ordered):
        mine = {(r["session_id"], r["step"]) for r in vr}
        failed = [r for r in final if (r["session_id"], r["step"]) in mine and r["verdict"] == "fail"
                  and (r.get("skill") or "unknown", r.get("skill_blob")) == (skill, blob)]
        if not failed:
            continue
        any_edit = True
        out += ["", f"### {label(skill, blob)}", ""]
        for step in sorted({r["step"] for r in failed}, key=step_key):
            where, edit = EDITS.get(step, ("the skill", "review this step against the failures below."))
            out.append(f"- {step}, in {where}: {edit} Failed in:")
            for r in sorted((r for r in failed if r["step"] == step), key=lambda r: r["session_id"]):
                out.append(f"  - {r['session_id'][:8]} ({r['session_id']}): {(r.get('evidence') or {}).get('why', '')}")
    if not any_edit:
        out += ["", "No step failed in any session, so no edit is proposed."]
    return "\n".join(out) + "\n"
