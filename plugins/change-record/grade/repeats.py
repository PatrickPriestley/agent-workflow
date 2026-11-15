"""repeats: how much of a session's closing message is said twice (record
docs/changes/2026-11-15-checkable-judges.md, R1).

A measure, not a verdict. Claude Sonnet is sent the brief in briefs/repeats.md and the closing
message, redacted by the caller, once, with no tools, no saved session and no settings, outside
any repository. It lists the points the message makes, each with a quote of where it is first
said and, when it is told a second time, a quote of where. Nothing it says is taken on trust:

  * a point counts only if its first quote is in the message that was sent;
  * a pair counts only if both quotes are in it and differ.

Quotes are compared after removing every backtick and asterisk, turning each run of white space
into one space and lowering the case, and in no other way. A pair's id is the first six hex
digits of the SHA-256 of the first quote, a line feed and the second quote, both so compared, so
that a person's ruling on a pair names the pair and not its place in a list.

The closing message is the last text the session itself wrote that is not empty, a subagent's
left out, which is what grade/measures.py counts as the last message. For a session cut off in
mid-work that is a progress note.
"""
import hashlib
import json
import os
import re
import subprocess
import tempfile

import fields
import judge

MEASURE = "repeats/1"  # bump when the counting changes; a changed brief is seen by its hash
MODEL = "sonnet"
BUDGET = 0.25   # dollars one call may spend
TIMEOUT = 300   # seconds
BRIEF = open(os.path.join(os.path.dirname(os.path.realpath(__file__)), "briefs", "repeats.md"), encoding="utf-8").read()
EMPTY = {"points": 0, "pairs": [], "said_again": 0, "quotes_not_found": 0, "same_quote_twice": 0, "share": None}


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def closing_message(lines):
    """(its entry in the transcript, its text), or None when the session wrote nothing."""
    _, texts, _ = fields.read(lines)
    written = [(n, t) for n, t in texts if t.strip()]
    return written[-1] if written else None


def norm(s):
    return re.sub(r"\s+", " ", s.replace("`", "").replace("*", "")).strip().lower()


def pair_id(first, again):
    return sha(norm(first) + "\n" + norm(again))[:6]


def count(answer, message):
    """The answer's points checked against the message; None when it holds no list of points."""
    m = re.search(r"\{.*\}", answer or "", re.S)
    try:
        points = json.loads(m.group(0))["points"] if m else None
    except (ValueError, KeyError, TypeError):
        points = None
    if not isinstance(points, list):
        return None
    body = norm(message)

    def found(q):
        return isinstance(q, str) and norm(q) and norm(q) in body
    n = missing = same = 0
    pairs = {}
    for p in points:
        first, again = (p.get("first"), p.get("again")) if isinstance(p, dict) else (None, None)
        if not found(first):
            missing += 1  # a point whose quote is not in the message is not a point of the message
            continue
        n += 1
        if again is None:
            continue
        if not found(again):
            missing += 1
        elif norm(again) == norm(first):
            same += 1
        else:
            pairs.setdefault(pair_id(first, again), {"id": pair_id(first, again), "first": first, "again": again})
    return {"points": n, "pairs": list(pairs.values()), "said_again": len(pairs), "quotes_not_found": missing,
            "same_quote_twice": same, "share": round(len(pairs) / n, 2) if n else None}


def ask(prompt):
    """One answer from Sonnet: {status: answer|refused|error, answer, served_model, cost_usd, detail}."""
    def got(status, answer="", served=None, cost=None, detail=None):
        return {"status": status, "answer": answer, "served_model": served, "cost_usd": cost, "detail": detail}
    cmd = ["claude", "-p", "--model", MODEL, "--output-format", "json", "--tools", "", "--no-session-persistence",
           "--setting-sources", "", "--max-budget-usd", str(BUDGET)]
    with tempfile.TemporaryDirectory(prefix="transcripts-repeats-") as cwd:
        try:
            r = subprocess.run(cmd, input=prompt, capture_output=True, text=True, timeout=TIMEOUT, cwd=cwd, env=judge.clean_env())
        except subprocess.TimeoutExpired:
            return got("error", detail=f"no answer in {TIMEOUT} s")
        except OSError as e:
            return got("error", detail=f"claude did not start ({e})")
    try:
        d = json.loads((r.stdout or "").strip().splitlines()[-1])
        if not isinstance(d, dict):
            raise ValueError
    except (ValueError, IndexError):
        return got("error", r.stdout or "", detail=f"exit {r.returncode}, and the output is not claude -p JSON")
    answer = d.get("result") if isinstance(d.get("result"), str) else ""
    served = ",".join(sorted(d.get("modelUsage") or {})) or None
    cost = d.get("total_cost_usd") if isinstance(d.get("total_cost_usd"), (int, float)) else None
    if d.get("stop_reason") == "refusal":
        return got("refused", answer, served, cost, "stop_reason refusal")
    if d.get("is_error") or r.returncode != 0:
        return got("error", answer, served, cost, f"exit {r.returncode}, terminal_reason {d.get('terminal_reason')}")
    if not served or not all(MODEL in m for m in served.split(",")):
        return got("error", answer, served, cost, f"served by {served or 'no model'}, not Sonnet")
    return got("answer", answer, served, cost)


def describe(text, redact):
    """The closing message as it is sent, and what identifies an answer to it."""
    message = redact(text)
    return message, {"characters": len(message), "sha256": sha(message)}


def judge_message(message, redact, asker=ask):
    """The measure for one redacted closing message: status counted, malformed, refused or error.
    The answer is kept redacted too: a model can write what it was not sent."""
    got = asker(BRIEF + message)
    doc = {"measure": MEASURE, "model": MODEL, "brief_sha256": sha(BRIEF), "served_model": got["served_model"],
           "cost_usd": got["cost_usd"], "detail": got["detail"], "answer": redact((got["answer"] or "")[:20000])}
    counted = count(got["answer"], message) if got["status"] == "answer" else None
    if counted is None:
        status = "malformed" if got["status"] == "answer" else got["status"]
        detail = got["detail"] or "the answer holds no JSON object with a list of points"
        return dict(doc, status=status, detail=detail, **EMPTY)
    return dict(doc, status="counted", **counted)


def answered(doc, described):
    """Whether a kept answer is for this brief and this message, and counted."""
    return (isinstance(doc, dict) and doc.get("status") == "counted" and doc.get("measure") == MEASURE
            and doc.get("brief_sha256") == sha(BRIEF) and (doc.get("message") or {}).get("sha256") == described["sha256"])
