"""The report over score rows (records docs/changes/2026-11-09-skill-transcripts.md, R11, and
docs/changes/2026-11-11-grading-trust.md, R4 and R5).

Rows are grouped by skill version, the skill's name and the git blob of its file, and two
versions are never counted together. Within a version each step is counted per grader, from the
latest row per session, step and grader. The agreement between the Haiku judge and the
agreement judge is counted from the judge files of sessions both judged, on the same record.

Beside each pass rate stands the grader's measured error: how often its verdict on the step
was wrong on the sessions a person labelled (labels.py), or "not yet checked" while fewer than
MIN_COVERED labelled sessions cover the step. A session where label and grader both say not
applicable covers nothing: no verdict was put to the test there.

For each step whose latest row for a session, whatever the grader, is a fail, the report shows
what the session did: the grader's reason, the rest of the row's evidence, and the calls the
evidence cites, each with a short excerpt from the transcript. It proposes no edit. Every text
taken from a row, a label or a transcript passes through the caller's redaction.
"""
import json
from datetime import datetime, timezone

import fields
import judge
import labels

ORDER = fields.STEPS + judge.QUESTIONS
MIN_COVERED = 5  # labelled sessions that must cover a step before its error is printed (R4)
# evidence keys that name one call. The lists of calls (probes, failing_runs) are empty whenever their step fails, and are
# printed with the rest of the evidence.
CITES = ("first_record_write", "first_code_write")
BEFORE = {"red-first": "first_code_write", "probe-before-record": "first_record_write"}  # the call a step's failure looks back from
NOT_SHOWN = ("why", "records_written", "records_named")
SHELL_SHOWN = 10
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


def measure(rows, checked):
    """Each field grader's rows against the labels: {grader: labels.compare(...)}.

    With no field grader among the rows the comparison still runs, under the key None, so that
    what the labels could not be counted for is reported.
    """
    graders = sorted({r["grader"] for r in rows if str(r["grader"]).startswith("fields/")}) or [None]
    out = {}
    for g in graders:
        mine = {}
        for r in rows:
            if r["grader"] == g:
                mine.setdefault(r["session_id"], []).append(r)
        here = {sid: {"sha256": sha, "lines": n, "rows": mine.get(sid)} for sid, (sha, n) in checked["here"].items()}
        out[g] = labels.compare(checked["labels"], here)
    return out


def error_of(measured, step, grader):
    """(covered, wrong, counts) for a step and grader, or None where the labels do not cover the grader's steps."""
    if grader not in measured or step not in fields.STEPS:
        return None
    c = measured[grader]["counts"][step]
    return c["labelled"] - c["both_na"], c["false_fail"] + c["false_pass"] + c["false_na"], c


def error_cell(measured, step, grader):
    e = error_of(measured, step, grader)
    if e is None:
        return "not yet checked (no labels)"
    covered, wrong, _ = e
    if covered < MIN_COVERED:
        return f"not yet checked ({covered} of {MIN_COVERED} needed)"
    return f"{round(100 * wrong / covered)}% ({wrong} of {covered} wrong)"


def name(sid):
    return f"{sid[:8]} ({sid})"


def error_section(measured, checked, pairs, rows, red):
    counted = sorted({s for res in measured.values() for s in res["sessions"]})
    n, several = len(counted), len(measured) > 1
    out = ["", "## Grader error", "",
           f"Each field grader's latest row for a session and step, against a person's label of that session. {n} "
           f"session{'s are' if n != 1 else ' is'} counted, of {len(checked['here'])} with a transcript here and {checked['files']} "
           "label files. A labelled session covers a step when its label or the grader says pass or fail; where both say not "
           "applicable nothing was put to the test, and it is counted apart. Wrong is a false fail (a fail the label does not "
           "share), a false pass (a pass the label does not share) or a false n/a (not applicable where the label says pass or "
           f"fail). A step covered by fewer than {MIN_COVERED} labelled sessions is not yet checked: nothing here says its "
           "verdicts are right.", "",
           "| Step | Grader | Covered | Wrong | Error | False fail | False pass | False n/a | Both n/a |", "|---|---|---|---|---|---|---|---|---|"]
    unlabelled = []
    for step, grader in pairs:
        e = error_of(measured, step, grader)
        if e is None:
            if step not in unlabelled:
                unlabelled.append(step)
            continue
        covered, wrong, c = e
        err = f"{round(100 * wrong / covered)}%" if covered >= MIN_COVERED else "not yet checked"
        out.append(f"| {step} | {grader} | {covered} | {wrong} | {err} | {c['false_fail']} | {c['false_pass']} | {c['false_na']} | {c['both_na']} |")
    if unlabelled:
        out += ["", f"The labels cover the field graders' steps only: {' and '.join(unlabelled)} "
                    f"{'are' if len(unlabelled) > 1 else 'is'} not yet checked."]
    out += ["", "### Known false verdicts", ""]
    found = False
    for g, res in measured.items():
        for d in res["disagreements"]:
            found = True
            out.append(f"- {d['step']}, {g + ', ' if several else ''}{d['kind'].replace('_', ' ').replace(' na', ' n/a')}, "
                       f"{name(d['session'])}: the label says {labels.SHOWN[d['label']]} ({red(d['reason'])}); the grader says "
                       f"{labels.SHOWN.get(d['grader'], d['grader'])} ({red(d['why'])})")
    if not found:
        out.append("None known: no counted label disagrees with a grader." if counted else
                   "None known, because no labelled session is counted: no verdict here has been checked.")
    out += ["", "### Not counted", ""]
    lines = [f"- {red(fname)} is rejected: {red(why)}" for fname, why in checked["problems"]]
    groups = {}
    for g, res in measured.items():
        for sid, step, why in res["not_counted"]:
            groups.setdefault((fields.STEPS.index(step) if step else -1, g if several else None, step, why), []).append(sid)
    for (_, g, step, why), sids in sorted(groups.items(), key=lambda kv: (kv[0][0], kv[0][1] or "")):
        lines.append(f"- {g + ', ' if g else ''}{step + ': ' if step else ''}{red(why)}, in {len(sids)} session{'s' if len(sids) != 1 else ''} "
                     f"({', '.join(s[:8] for s in sids)})")
    out += (lines or ["Nothing."]) + ["", "### Rows that are no verdict", ""]
    could_not = {}
    for r in rows:
        err = (r.get("evidence") or {}).get("error") if isinstance(r.get("evidence"), dict) else None
        if err:
            could_not.setdefault((step_key(r["step"]), r["step"], r["grader"], str(err)), []).append(r["session_id"])
    for (_, step, g, err), sids in sorted(could_not.items()):
        out.append(f"- {step}, {g}: {red(err)}, in {len(sids)} session{'s' if len(sids) != 1 else ''} "
                   f"({', '.join(s[:8] for s in sorted(sids))}): its not applicable there is no verdict")
    return out + ([] if could_not else ["None: no row here says its grader could not read what it needed."])


def shown(value):
    if value is None or value == [] or value == "":
        return "none"
    if isinstance(value, list):
        return ", ".join(str(v) for v in value)
    if isinstance(value, dict):
        return json.dumps(value, ensure_ascii=False)
    return str(value)


def cited(evidence):
    """[(key, call id, files)] for each call the evidence cites."""
    out = []
    for key in CITES:
        v = evidence.get(key)
        if isinstance(v, dict) and v.get("call"):
            out.append((key, str(v["call"]), [str(f) for f in v.get("files") or []]))
        elif isinstance(v, str) and v:
            out.append((key, v, []))
    return out


def one_line(text, width=120):
    lines = [ln.strip() for ln in str(text).splitlines() if ln.strip()]
    if not lines:
        return ""
    return (lines[0][:width] + " [...]") if len(lines[0]) > width or len(lines) > 1 else lines[0]


def excerpt(n, c, red):
    """A call's input and result, cut short."""
    name_, inp = c["name"], c["input"]
    if name_ == "Bash":
        body = labels.clip(red(str(inp.get("command") or "")), 4, 1)
    elif name_ == "Write":
        body = labels.clip(red(str(inp.get("content") or "")), 4)
    elif name_ in ("Edit", "MultiEdit"):
        edits, body = inp.get("edits") if isinstance(inp.get("edits"), list) else [inp], []
        for e in [e for e in edits if isinstance(e, dict)][:2]:
            body += ["- " + ln for ln in labels.clip(red(str(e.get("old_string") or "")), 3)]
            body += ["+ " + ln for ln in labels.clip(red(str(e.get("new_string") or "")), 3)]
    else:
        body = labels.clip(red(json.dumps(inp, ensure_ascii=False)), 2, 0, 200)
    out = labels.block(body) + [""]
    if c["result"] is None:
        return out + ["It has no result: the call was never answered."]
    return out + ["Result, flagged as an error:" if c["is_error"] else "Result:", ""] + labels.block(labels.clip(red(c["result"]), 3, 2))


def shell_before(calls, anchor, red):
    """One line for each shell command before call number anchor: the command and how it ended."""
    shell = [(n, c) for n, c in calls if c["name"] == "Bash" and n < anchor]
    out = ["", f"Shell commands before [{anchor}]:" if shell else f"No shell command came before [{anchor}].", ""]
    if len(shell) > SHELL_SHOWN:
        out.append(f"- [... {len(shell) - SHELL_SHOWN} earlier ones are left out]")
    for n, c in shell[-SHELL_SHOWN:]:
        res = c["result"]
        if res is None:
            how = "never answered"
        elif fields.DENIAL.match(res):
            how = "denied or refused"
        else:
            got = [ln.strip() for ln in red(res).splitlines() if ln.strip()]
            how = "flagged as an error" if c["is_error"] else "ran"
            if not got:
                how += "; it printed nothing"
            elif len(got) == 1:
                how += f"; its result is `{got[0][:120]}`"
            else:
                how += f"; its result opens `{got[0][:120]}` and ends `{got[-1][:120]}`"
        out.append(f"- [{n}] `{one_line(red(str(c['input'].get('command') or '')))}`: {how}")
    return out[:-1] if not shell else out


def failed_step(r, cell, false_fail, votes, read, red):
    """What the session did where row r says fail."""
    ev = r.get("evidence") if isinstance(r.get("evidence"), dict) else {}
    out = ["", f"#### {r['step']}, {name(r['session_id'])}", "",
           f"{r['grader']} says fail: {red(str(ev.get('why') or 'it gives no reason'))}", ""]
    line = f"Its error on this step: {cell}."
    if false_fail:
        line += (f" A person's label says {labels.SHOWN[false_fail['label']]} ({red(false_fail['reason'])}): "
                 "this fail is a known false fail.")
    out.append(line)
    cites = cited(ev)
    rest = [f"{k} {red(shown(v))[:200]}" for k, v in ev.items()
            if k not in NOT_SHOWN and not (k in CITES and any(key == k for key, _, _ in cites))]
    if rest:
        out += ["", f"Its evidence: {'; '.join(rest)}."]
    if votes:
        out += ["", "Its votes:", ""]
        for v in votes:
            if v.get("status", "vote") == "vote":
                out.append(f"- vote {v.get('vote')}, {v.get('verdict')}: {red(str(v.get('reason') or ''))}")
            else:
                out.append(f"- vote {v.get('vote')}, not counted ({v.get('status')}): {red(str(v.get('detail') or ''))}")
    if str(r["grader"]).startswith("judge/"):
        return out
    if not cites:
        return out + ["", "It cites no call."]
    try:
        lines = read(r["session_id"]) if read else None
        calls = None if lines is None else [(n, c) for kind, n, c in labels.events(lines) if kind == "call"]
        why_not = "The transcript is not here"
    except fields.Unparsable as e:
        calls, why_not = None, f"The transcript cannot be read ({e})"
    if calls is None:
        return out + ["", f"{why_not}, so the calls are named and not shown: " + ", ".join(f"{k} `{red(i)}`" for k, i, _ in cites) + "."]
    by_id, anchor = {}, None
    for n, c in calls:
        by_id.setdefault(c["id"], (n, c))
    for key, cid, files in cites:
        what = key + (f" ({red(', '.join(files))})" if files else "")
        if cid not in by_id:
            out += ["", f"{what}, `{red(cid)}`: not among the calls of the transcript here."]
            continue
        n, c = by_id[cid]
        if key == BEFORE.get(r["step"]):
            anchor = n
        path = str(c["input"].get("file_path") or c["input"].get("notebook_path") or "")
        out += ["", f"{what}, **[{n}] {c['name']}** `{red(cid)}`" + (f" {red(path)}" if path else "") + ":", ""] + excerpt(n, c, red)
    if anchor is not None:
        out += shell_before(calls, anchor, red)
    return out


def build(rows, entries, judges, checked=None, read=None, redact=None):
    """The report as Markdown, or None when there is no score row.

    checked: what the graders are checked against: {"labels": {sessionId: label}, "problems":
    [(label file, why it is rejected)], "files": how many label files there are, "here":
    {sessionId: (sha256, lines)} for each session whose transcript is here}. read(sessionId): that
    transcript's lines, or None. redact: applied to every text from a row, a label or a transcript.
    """
    red = redact or (lambda t: t)
    checked = checked or {"labels": {}, "problems": [], "files": 0, "here": {}}
    rows = latest(rows, lambda r: (r["session_id"], r["step"], r["grader"]))
    if not rows:
        return None
    measured = measure(rows, checked)
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
           "with not applicable counted apart. Each step keeps the latest row per session and grader. Grader error is how "
           "often that grader's verdict on the step was wrong on the sessions a person labelled, over every version together "
           f"(the Grader error section has the counts); \"not yet checked\" means fewer than {MIN_COVERED} labelled sessions "
           "cover the step, and says nothing for or against its verdicts."]
    pairs_all = sorted({(r["step"], r["grader"]) for r in rows}, key=lambda p: (step_key(p[0]), p[1]))
    for (skill, blob), vr in ordered:
        ss = v_sessions(vr)
        times = [s_time[s] for s in ss if s in s_time]
        out += ["", f"## {label(skill, blob)}", "",
                f"Sessions: {len(ss)}, from {day(min(times) if times else None)} to {day(max(times) if times else None)}.", "",
                "| Step | Grader | Pass | Fail | N/A | Pass rate | Grader error |", "|---|---|---|---|---|---|---|"]
        for step, grader in [p for p in pairs_all if any(r["step"] == p[0] and r["grader"] == p[1] for r in vr)]:
            p, f, n = counts(vr, step, grader)
            out.append(f"| {step} | {grader} | {p} | {f} | {n} | {rate(p, f)} | {error_cell(measured, step, grader)} |")

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

    out += error_section(measured, checked, pairs_all, rows, red)

    out += ["", "## Failed steps", "",
            "Each session and step whose latest row, whatever the grader, is a fail, per skill version, newest first: the "
            "grader's reason, the rest of its evidence, and the calls it cites, each with a redacted excerpt from the "
            "transcript. [n] is the call's number in the session's label sheet. A fail is a grader's verdict, to be read "
            "against that grader's error above. No edit is proposed: what to change, if anything, is the reader's to decide "
            "from what the session did."]
    false_fails = {(g, d["session"], d["step"]): d for g, res in measured.items() for d in res["disagreements"] if d["kind"] == "false_fail"}

    def votes_of(r):
        mine = [j for j in judges if j.get("session_id") == r["session_id"] and f"{j.get('judge')}:{j.get('model')}" == r["grader"]]
        mine.sort(key=lambda j: when(j.get("judged_at")) or datetime.min.replace(tzinfo=timezone.utc))
        q = ((mine[-1].get("questions") or {}).get(r["step"]) or {}) if mine else {}
        return [v for v in q.get("votes") or [] if isinstance(v, dict)]

    final = latest(rows, lambda r: (r["session_id"], r["step"]))
    any_failed = False
    for (skill, blob), vr in reversed(ordered):
        mine = {(r["session_id"], r["step"]) for r in vr}
        failed = [r for r in final if (r["session_id"], r["step"]) in mine and r["verdict"] == "fail"
                  and (r.get("skill") or "unknown", r.get("skill_blob")) == (skill, blob)]
        if not failed:
            continue
        any_failed = True
        out += ["", f"### {label(skill, blob)}"]
        for r in sorted(failed, key=lambda r: (step_key(r["step"]), r["session_id"])):
            out += failed_step(r, error_cell(measured, r["step"], r["grader"]),
                               false_fails.get((r["grader"], r["session_id"], r["step"])), votes_of(r), read, red)
    if not any_failed:
        out += ["", "No step's latest row is a fail."]
    return "\n".join(out) + "\n"
