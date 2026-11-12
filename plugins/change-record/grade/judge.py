"""The judge for the two questions no regex settles (record docs/changes/2026-11-09-skill-transcripts.md,
R10 and C3): whether the record's Decisions name a rejected alternative, and whether its Outcome
quotes real output.

A fresh Claude Haiku session answers each question three times (`claude -p --model haiku` with
no tools, no saved session and no settings, outside any repository); the agreement check asks
opencode-go/kimi-k3.1-pro the same prompts through `opencode run` with an agent that may use no
tool. Everything a judge sees passes through the caller's redaction first.

An answer counts as a vote only when it is one JSON object, alone or in a single code fence,
with "verdict" "pass" or "fail" and a string "reason", and nothing else. A refusal, an error, an
answer from a model that is not the one asked for, and anything else are kept with their text
and not counted. Two counted votes that agree make the verdict; otherwise it is undecided and no
score row is written.
"""
import hashlib
import json
import os
import re
import subprocess
import tempfile

JUDGE = "judge/1"  # bump when a prompt or the counting changes, so verdicts from two versions are not mixed
VOTES = 3
TIMEOUT = 180  # seconds per answer
MODELS = {"claude": "haiku", "opencode": "opencode-go/kimi-k3.1-pro"}
QUESTIONS = ["decisions-alternative", "outcome-real-output"]
SECTION_CAP = 12000  # characters of a section a judge sees
COMMANDS_CAP = 60    # the last commands the session ran, for the Outcome question
PASS, FAIL, NA, UNDECIDED = "pass", "fail", "not_applicable", "undecided"

SYSTEM = ("You judge one question about a software change record. Answer with one line of JSON and "
          'nothing else: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.')
ASK = {
    "decisions-alternative": (
        "Decisions",
        "Question: does the record's Decisions section name, for at least one decision, an alternative "
        "that was considered and rejected, with a reason?\n"
        'PASS if at least one decision names a rejected alternative and why (for example "Rejected: X, '
        'because Y", or "rather than X, since Y"). FAIL if the section is empty, holds only placeholders, '
        "or lists decisions with no rejected alternative. A rejected alternative named without any reason "
        "for rejecting it does not count: if that is all the section has, FAIL."),
    "outcome-real-output": (
        "Outcome",
        "Question: does the record's Outcome quote real runs of what the change built: the commands run "
        "and the output they printed, rather than only describing the result or reporting test counts?\n"
        "PASS if the Outcome quotes at least one command and the output it printed. FAIL if it only "
        "describes behaviour, only reports unit-test results, or holds no output."),
}
REFUSAL = re.compile(r"\b(?:I\s+(?:can(?:no|')t|cannot|won't|will\s+not|am\s+not\s+able\s+to|'m\s+not\s+able\s+to)"
                     r"\s+(?:help|assist|comply|do\s+that)|can't\s+help\s+with\s+this)", re.I)


def section(text, name):
    """A level-2 section's body, comments and the template's hint lines left out."""
    m = re.search(r"^## %s[ \t]*\n(.*?)(?=^## |\Z)" % re.escape(name), text or "", re.M | re.S)
    body = re.sub(r"<!--.*?-->", "", m.group(1), flags=re.S) if m else ""
    lines = [ln for ln in body.splitlines() if not ln.startswith("Filled at the end:")]
    return "\n".join(lines).strip()


def cap(text, n):
    return text if len(text) <= n else text[:n] + f"\n[... cut at {n} characters]"


def prompt_for(question, record_path, record_text, commands, redact):
    name, ask = ASK[question]
    tag = name.lower()
    parts = [SYSTEM, "", ask, "", f"The record: {record_path}", "",
             f"<{tag}>", cap(section(record_text, name), SECTION_CAP), f"</{tag}>"]
    if question == "outcome-real-output":
        parts += ["", "Commands the session ran, for reference (a command the Outcome quotes should be among them):",
                  "<commands>"] + ["$ " + c for c in commands[-COMMANDS_CAP:]] + ["</commands>"]
    parts += ["", 'Answer with one line of JSON: {"reason": "<one sentence>", "verdict": "pass" or "fail"}.']
    return redact("\n".join(parts))


def parse_answer(text):
    """(verdict, reason) when the answer is exactly one well-formed JSON object, else None."""
    t = (text or "").strip()
    m = re.fullmatch(r"```(?:json)?[ \t]*\n(.*?)\n[ \t]*```", t, re.S)
    if m:
        t = m.group(1).strip()
    try:
        obj = json.loads(t)
    except ValueError:
        return None
    if (not isinstance(obj, dict) or set(obj) != {"verdict", "reason"} or obj["verdict"] not in (PASS, FAIL)
            or not isinstance(obj["reason"], str)):
        return None
    return obj["verdict"], obj["reason"]


def vote(status, answer, verdict=None, reason=None, served=None, detail=None):
    return {"status": status, "verdict": verdict, "reason": reason, "answer": (answer or "")[:4000],
            "served_model": served, "detail": detail}


def read_claude(stdout, rc, model="haiku", parse=None):
    """One `claude -p --output-format json` answer as a vote record; it must come from the model asked for."""
    try:
        d = json.loads((stdout or "").strip().splitlines()[-1])
        if not isinstance(d, dict):
            raise ValueError
    except (ValueError, IndexError):
        return vote("error", stdout, detail=f"exit {rc}, and the output is not claude -p JSON")
    answer = d.get("result") if isinstance(d.get("result"), str) else ""
    served = ",".join(sorted(d.get("modelUsage") or {})) or None
    if d.get("stop_reason") == "refusal":
        return vote("refused", answer, served=served, detail="stop_reason refusal")
    if d.get("is_error") or rc != 0:
        return vote("error", answer, served=served, detail=f"exit {rc}, terminal_reason {d.get('terminal_reason')}")
    if not served or not all(model in m for m in served.split(",")):
        return vote("error", answer, served=served, detail=f"served by {served or 'no model'}, not {model.capitalize()}")
    return read_text(answer, served, parse)


def read_text(answer, served, parse=None):
    got = (parse or parse_answer)(answer)
    if got:
        return vote("vote", answer, verdict=got[0], reason=got[1], served=served)
    if REFUSAL.search(answer or ""):
        return vote("refused", answer, served=served, detail="the answer declines")
    return vote("malformed", answer, served=served, detail="not one JSON object with verdict pass or fail and a reason")


def read_opencode(stdout, rc, model):
    if rc != 0:
        return vote("error", stdout, served=model, detail=f"exit {rc}")
    return read_text(stdout, model)


def clean_env():
    """The judge's environment: no archive, so its own session is never captured, and no project."""
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("AGENT_TRANSCRIPTS") and k not in ("CLAUDE_PROJECT_DIR", "OPENCODE_CONFIG", "OPENCODE_CONFIG_DIR")}
    return env


def ask(kind, prompt, model=None, system=None, parse=None):
    """One answer from the judge, as a vote record. Runs in a fresh empty directory. model, system
    and parse are the rubric judge's (grade/rubric.py): another Claude model, its own instruction
    and its own reading of the answer."""
    model = model or MODELS[kind]
    env = clean_env()
    with tempfile.TemporaryDirectory(prefix="transcripts-judge-") as cwd:
        if kind == "claude":
            cmd = ["claude", "-p", "--model", model, "--output-format", "json", "--tools", "",
                   "--no-session-persistence", "--setting-sources", "", "--system-prompt", system or SYSTEM]
            stdin = prompt
        else:
            agent = "transcriptsjudge-" + os.urandom(8).hex()
            env.update(OPENCODE_DISABLE_PROJECT_CONFIG="1", OPENCODE_DISABLE_AUTOUPDATE="1",
                       OPENCODE_CONFIG_CONTENT=json.dumps({"agent": {agent: {
                           "mode": "primary", "description": "judge, no tools", "permission": {"*": "deny"}}}}))
            cmd = ["opencode", "run", "--agent", agent, "-m", model, prompt]
            stdin = ""
        try:
            r = subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=TIMEOUT, cwd=cwd, env=env)
        except subprocess.TimeoutExpired:
            return vote("error", "", served=None, detail=f"no answer in {TIMEOUT} s")
        except OSError as e:
            return vote("error", "", served=None, detail=f"{cmd[0]} did not start ({e})")
    if kind == "claude":
        v = read_claude(r.stdout, r.returncode, model if model != MODELS["claude"] else "haiku", parse)
    else:
        v = read_opencode(r.stdout, r.returncode, model)
    if v["status"] == "error" and r.stderr.strip():
        v["detail"] = (v["detail"] or "") + "; stderr: " + r.stderr.strip()[-300:]
    return v


def decide(votes):
    counted = [v for v in votes if v["status"] == "vote"]
    for verdict in (PASS, FAIL):
        agree = [v for v in counted if v["verdict"] == verdict]
        if len(agree) >= 2:
            return verdict, f"{len(agree)} of {len(votes)} votes {verdict}: {agree[0]['reason']}"
    return UNDECIDED, f"{len(counted)} of {len(votes)} answers counted as votes, and no two agree"


def judge_record(kind, record_path, record_text, commands, outcome_state, redact, asker=ask, keep=None):
    """Both questions for one record. outcome_state: "judge", "empty" or "not_done" (from the
    outcome-filled step). Returns {question: {verdict, why, prompt, prompt_sha256, votes}}.
    keep: the questions as an earlier run of the same record left them; one that votes decided
    is returned as it is and not asked again."""
    out = {}
    for q in QUESTIONS:
        name = ASK[q][0]
        if keep and (keep.get(q) or {}).get("verdict") in (PASS, FAIL) and keep[q].get("votes"):
            out[q] = keep[q]
            continue
        if q == "outcome-real-output" and outcome_state == "not_done":
            out[q] = {"verdict": NA, "why": "the record is not done", "votes": []}
            continue
        if not section(record_text, name):
            out[q] = {"verdict": FAIL, "why": f"the {name} section is empty", "votes": []}
            continue
        p = prompt_for(q, record_path, record_text, commands, redact)
        votes = []
        for i in range(VOTES):
            v = asker(kind, p)
            v["vote"] = i + 1
            votes.append(v)
        verdict, why = decide(votes)
        out[q] = {"verdict": verdict, "why": why, "prompt": p,
                  "prompt_sha256": hashlib.sha256(p.encode()).hexdigest(), "votes": votes}
    return out
