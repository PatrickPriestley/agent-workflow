"""rubric: a judged rubric for a session's code (record
docs/changes/2026-11-12-session-quality.md, R4, R5 and its concerns C2, C4, C6, C7).

  code-quality  asked of the diff between the session's first and last commit, of Claude Sonnet

It is asked three times in a fresh session with no tools (as grade/judge.py asks its
questions), and answers with one of the rubric's labels and a reason. Two answers with the
same label decide; anything else is undecided and writes no verdict. The rubric texts are in
grade/rubrics/, adapted from Skill Doctor's scorers (MIT).

A second rubric, verbosity, was asked of the session's messages, of Claude Haiku, until
2026-11-12. Measured against 14 labelled sessions it answered proportionate every time and
was wrong on 3, more than the one in five the record allows a judge (C2), so it is not asked
and not reported, and it was not tuned. Its text stays in grade/rubrics/ and a label file may
still carry its line: the labels are what it was measured against.

A label is good or it is not: the first label of a rubric is a pass and the others a fail, so
a verdict fits the store's score rows and can be checked against a person's label like any
step. The report shows the labels themselves; they carry no number and are never averaged.

What a judge sees passes through the caller's redaction first.
"""
import hashlib
import json
import os
import re

import fields
import judge

RUBRIC = "rubric/1"  # bump when a rubric's text, its input or the counting changes
QUESTIONS = ["code-quality"]  # what is asked and reported
RETIRED = ["verbosity"]       # taken out (C2): labels for it still load, nothing else reads it
MODEL = {"code-quality": "sonnet"}
DIFF_CAP = 60000  # characters of diff a judge sees (C4)
VOTES = judge.VOTES
PASS, FAIL, UNDECIDED = judge.PASS, judge.FAIL, judge.UNDECIDED
HERE = os.path.dirname(os.path.realpath(__file__))
LEFT_OUT = re.compile(r"(?:^|/)(?:fixtures|testdata|results|node_modules|vendor|dist|build)/|(?:^|/)[^/]*expected[^/]*$"
                      r"|\.(?:lock|min\.js|map|gz|zip|png|jpg|jpeg|gif|pdf|ico|svg)$|(?:^|/)package-lock\.json$")


def load(question):
    """(labels, text) of a rubric file: the allowed answers, good first, and what the judge reads."""
    raw = open(os.path.join(HERE, "rubrics", question + ".md"), encoding="utf-8").read()
    end = raw.index("\n---", 4)
    m = re.search(r"^labels: \[(.*)\]\s*$", raw[4:end], re.M)
    return [w.strip() for w in m.group(1).split(",")], raw[end + 4:].strip()


LABELS = {q: load(q)[0] for q in QUESTIONS + RETIRED}


def verdict_of(question, label):
    return PASS if label == LABELS[question][0] else FAIL


def system(question):
    return (f"You judge one coding-agent session against one rubric. Answer with one line of JSON and nothing else: "
            f'{{"reason": "<one to three sentences>", "label": {" or ".join(json.dumps(w) for w in LABELS[question])}}}.')


def rank(path):
    """Code first, then tests, then the rest: the order a diff over the limit is kept in."""
    return {"code": 0, "test": 1}.get(fields.kind(path), 2)


def select_diff(files):
    """What of a diff a judge sees. files: [(path, that file's diff)], in git's order.
    Returns (text, partial, left_out): under the limit, all of it; over it, generated and
    fixture files are left out (and named) and the rest is kept code first, whole files, up
    to the limit; partial is True when a file that is neither was cut or dropped."""
    whole = "".join(d for _, d in files)
    if len(whole) <= DIFF_CAP:
        return whole, False, []
    left_out = [p for p, _ in files if LEFT_OUT.search(p)]
    rest = sorted((f for f in files if not LEFT_OUT.search(f[0])), key=lambda f: rank(f[0]))
    kept, size, partial = [], 0, False
    for path, d in rest:
        if size + len(d) <= DIFF_CAP:
            kept.append(d)
            size += len(d)
        else:
            partial = True
            if not kept:  # one file larger than the limit: its start is better than nothing
                kept.append(d[:DIFF_CAP] + f"\n[... {path} cut at {DIFF_CAP} characters]\n")
                size = DIFF_CAP
    return "".join(kept), partial, left_out


def prompt_for(question, material, partial, context, redact):
    _, text = load(question)
    parts = [system(question), "", text, "", context, ""]
    if partial:
        parts += ["This is a part of a larger change: it did not fit, and what is shown was kept code first.", ""]
    parts += ["<diff>", material, "</diff>", "",
              f'Answer with one line of JSON: {{"reason": "...", "label": {" or ".join(json.dumps(w) for w in LABELS[question])}}}.']
    return redact("\n".join(parts))


def parser(question):
    def parse(text):
        """(label, reason) when the answer is exactly one JSON object with a label of this rubric, else None."""
        t = (text or "").strip()
        m = re.fullmatch(r"```(?:json)?[ \t]*\n(.*?)\n[ \t]*```", t, re.S)
        if m:
            t = m.group(1).strip()
        try:
            obj = json.loads(t)
        except ValueError:
            return None
        if (not isinstance(obj, dict) or set(obj) != {"label", "reason"} or obj["label"] not in LABELS[question]
                or not isinstance(obj["reason"], str)):
            return None
        return obj["label"], obj["reason"]
    return parse


def decide(votes):
    """(label or None, why): the label two counted answers share."""
    counted = [v for v in votes if v["status"] == "vote"]
    for label in sorted({v["verdict"] for v in counted}):
        agree = [v for v in counted if v["verdict"] == label]
        if len(agree) >= 2:
            return label, f"{len(agree)} of {len(votes)} votes {label}: {agree[0]['reason']}"
    return None, f"{len(counted)} of {len(votes)} answers counted as votes, and no two give the same label"


def judge_question(question, material, partial, context, redact, asker=None):
    """One rubric for one session: {label, verdict, why, model, partial, prompt, prompt_sha256, votes}."""
    asker = asker or judge.ask
    p = prompt_for(question, material, partial, context, redact)
    votes = []
    for i in range(VOTES):
        v = asker("claude", p, model=MODEL[question], system=system(question), parse=parser(question))
        v["vote"] = i + 1
        votes.append(v)
    label, why = decide(votes)
    return {"label": label, "verdict": verdict_of(question, label) if label else UNDECIDED, "why": why,
            "model": MODEL[question], "partial": partial, "prompt": p,
            "prompt_sha256": hashlib.sha256(p.encode()).hexdigest(), "votes": votes}
