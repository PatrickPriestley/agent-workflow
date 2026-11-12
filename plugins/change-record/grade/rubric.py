"""rubric: two judged rubrics for a session's code and prose (record
docs/changes/2026-11-12-session-quality.md, R4, R5 and its concerns C2, C4, C6, C7).

  code-quality  asked of the diff between the session's first and last commit, of Claude Sonnet
  verbosity     asked of the messages the session wrote, with its counts, of Claude Haiku

Each is asked three times in a fresh session with no tools (as grade/judge.py asks its
questions), and answers with one of the rubric's labels and a reason. Two answers with the
same label decide; anything else is undecided and writes no verdict. The rubric texts are in
grade/rubrics/, adapted from Skill Doctor's scorers (MIT).

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
QUESTIONS = ["code-quality", "verbosity"]
MODEL = {"code-quality": "sonnet", "verbosity": "haiku"}
DIFF_CAP = 60000      # characters of diff a judge sees (C4)
MESSAGES_CAP = 40000  # characters of the session's messages a judge sees
PASS, FAIL, NA, UNDECIDED = judge.PASS, judge.FAIL, judge.NA, judge.UNDECIDED
HERE = os.path.dirname(os.path.realpath(__file__))
LEFT_OUT = re.compile(r"(?:^|/)(?:fixtures|testdata|results|node_modules|vendor|dist|build)/|(?:^|/)[^/]*expected[^/]*$"
                      r"|\.(?:lock|min\.js|map|gz|zip|png|jpg|jpeg|gif|pdf|ico|svg)$|(?:^|/)package-lock\.json$")


def load(question):
    """(labels, text) of a rubric file: the allowed answers, good first, and what the judge reads."""
    raw = open(os.path.join(HERE, "rubrics", question + ".md"), encoding="utf-8").read()
    end = raw.index("\n---", 4)
    m = re.search(r"^labels: \[(.*)\]\s*$", raw[4:end], re.M)
    return [w.strip() for w in m.group(1).split(",")], raw[end + 4:].strip()


LABELS = {q: load(q)[0] for q in QUESTIONS}


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


def select_messages(texts):
    """(text, partial) of the session's messages, numbered; over the limit the first and the last are kept."""
    shown = [f"[{i}] {t.strip()}" for i, t in enumerate((t for t in texts if t.strip()), 1)]
    whole = "\n\n".join(shown)
    if len(whole) <= MESSAGES_CAP:
        return whole, False
    half = MESSAGES_CAP // 2
    return whole[:half] + f"\n\n[... {len(whole) - MESSAGES_CAP} characters of messages left out ...]\n\n" + whole[-half:], True


def prompt_for(question, material, partial, context, redact):
    _, text = load(question)
    tag = "diff" if question == "code-quality" else "messages"
    parts = [system(question), "", text, ""]
    if context:
        parts += [context, ""]
    if partial:
        parts += ["This is a part of a larger change: it did not fit, and what is shown was kept code first."
                  if tag == "diff" else "These are the first and the last of the session's messages: the middle did not fit.", ""]
    parts += [f"<{tag}>", material, f"</{tag}>", "",
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
    for i in range(judge.VOTES):
        v = asker("claude", p, model=MODEL[question], system=system(question), parse=parser(question))
        v["vote"] = i + 1
        votes.append(v)
    label, why = decide(votes)
    return {"label": label, "verdict": verdict_of(question, label) if label else UNDECIDED, "why": why,
            "model": MODEL[question], "partial": partial, "prompt": p,
            "prompt_sha256": hashlib.sha256(p.encode()).hexdigest(), "votes": votes}


def not_asked(question, error):
    """A question that could not be put: no verdict, said as an error like a field step's."""
    return {"label": None, "verdict": NA, "why": error, "error": error, "model": MODEL[question], "partial": False, "votes": []}
