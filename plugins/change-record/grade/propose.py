"""propose: a skill edit drafted from one failure that a person's label confirms.

Record docs/changes/2026-11-12-session-quality.md, R6, R7 and concern C5. The graders have been
wrong often enough that an edit is never drafted from a grader's verdict alone: `transcripts
propose` asks for a label, by a named person, that says the session failed the step. The draft is
a file for the owner, written beside the transcripts and never into the skill. It enters the
skill only as a change of its own, and is kept only if the eval case that shows the failure
improves with it, run with and without the edit.

What goes to the model is what a label sheet shows, redacted as for the store: the skill file
the session used, the step and its rule, the labeller's reason, and the session's calls. One
call to Claude Sonnet, with no tools.
"""
import difflib
import json
import re
import subprocess
import tempfile

import judge

PROPOSE = "propose/1"  # bump when the prompt or the reading of the answer changes
MODEL = "sonnet"
BUDGET = 0.5      # dollars one call may spend
TIMEOUT = 300     # seconds
SHEET_CAP = 60000  # characters of the session's sheet that are sent: its end, where the calls are
EVALS_DIR = "plugins/change-record/evals"
# The eval case that shows a failure of each step, where there is one. A step that is not here has none.
EVALS = {"red-first": "red-first", "record-before-code": "record-before-code"}
# What each step asks, in the words of the README's table of steps (a test holds the two together).
RULES = {
    "tier-declared": "the record at the session's last commit has tier 0, 1 or 2",
    "probe-before-record": "ran before the session first wrote its record",
    "record-before-code": "the record was written before the first code",
    "red-first": "a test run, before the first code, ran and reported a failed test",
    "change-line": "opens with `Change: <record>`",
    "record-check": "`record-check` passes on the session's first to last commit",
    "outcome-filled": "has an Outcome",
}
BRIEF = """You are asked to improve the text of a skill: the instructions an AI coding agent loads before it changes code.

One session that had this skill loaded failed one of the steps the skill asks for. A person read the session and
confirmed the failure. Propose the smallest edit to the skill's text that would have made an agent in that session
do the step. Do not add a rule for anything else. Do not remove what the skill already asks. Keep its front matter,
its headings and its voice. If the skill already says plainly what the session did not do, say so in <why> and make
the wording harder to miss where the session went wrong; do not pad it.

Answer with exactly these three blocks and nothing after them:

<skill>
the whole proposed skill file
</skill>
<why>two or three sentences: what in the skill's text let the failure happen, and what the edit changes</why>
<calls>the numbers of the calls in the session, as the sheet numbers them, that show the failure, separated by commas</calls>
"""


def prompt_for(skill_name, skill_text, step, reason, sheet, redact):
    """The one message sent. Every part that came from a session or a person passes through redact."""
    return "\n".join([
        BRIEF,
        f"The skill is {skill_name}. Its file as the session used it:", "<current-skill>", redact(skill_text.rstrip("\n")), "</current-skill>", "",
        f"The step it failed is `{step}`. The step passes when: {RULES[step]}.", "",
        "What the person who labelled the session wrote:", "<label>", redact(reason), "</label>", "",
        "The session, as the label sheet shows it (redacted; cut to its end if long):", "<session>",
        redact(sheet)[-SHEET_CAP:], "</session>", ""])


def ask(prompt):
    """One answer from Sonnet: {status: answer|refused|error, answer, served_model, cost_usd, detail}."""
    def got(status, answer="", served=None, cost=None, detail=None):
        return {"status": status, "answer": answer, "served_model": served, "cost_usd": cost, "detail": detail}
    cmd = ["claude", "-p", "--model", MODEL, "--output-format", "json", "--tools", "", "--no-session-persistence",
           "--setting-sources", "", "--max-budget-usd", str(BUDGET)]
    with tempfile.TemporaryDirectory(prefix="transcripts-propose-") as cwd:
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


def read_answer(text, current):
    """(proposed skill file, why, sorted call numbers) from an answer; ValueError with the reason when it gives no edit."""
    m = re.search(r"<skill>\n?(.*?)\n?</skill>", text, re.S)
    if not m or not m.group(1).strip():
        raise ValueError("the answer holds no proposed skill file")
    skill = m.group(1).strip("\n") + "\n"
    if skill.strip() == current.strip():
        raise ValueError("the proposed skill file changes nothing")
    why = re.search(r"<why>(.*?)</why>", text, re.S)
    calls = re.search(r"<calls>(.*?)</calls>", text, re.S)
    return skill, " ".join((why.group(1) if why else "").split()), sorted({int(n) for n in re.findall(r"\d+", calls.group(1) if calls else "")})


def diff(current, proposed, name):
    return "".join(difflib.unified_diff(current.splitlines(keepends=True), proposed.splitlines(keepends=True),
                                        f"{name} (as the session used it)", f"{name} (proposed)"))


def some(numbers):
    """"calls 1 and 2", "call 3", or that none was named."""
    if not numbers:
        return "no call was named"
    words = [str(n) for n in numbers]
    return ("call " + words[0]) if len(words) == 1 else "calls " + ", ".join(words[:-1]) + " and " + words[-1]


def note(sid, step, skill_name, blob, by, reason, why, calls, got):
    """The proposal's own page: what it is drafted from, why, and the eval case that must show it helps (R7)."""
    case = EVALS.get(step)
    cost = f", ${got['cost_usd']:.2f}" if got.get("cost_usd") is not None else ""
    return "\n".join([
        f"# Proposed edit to {skill_name}", "",
        f"- Session: {sid}",
        f"- Skill file: blob {blob[:12]}, the version the session used; if the skill has changed since, make the edit "
        "again on the file as it is now",
        f"- Step it failed: `{step}` (passes when: {RULES[step]})",
        f"- Confirmed by: {by}: \"{reason}\"",
        f"- Where: {some(calls)} of the session's sheet (`transcripts sheet`)",
        f"- Drafted by: {got.get('served_model') or MODEL}{cost} ({PROPOSE})", "",
        "## Why this edit", "", why or "The answer gave no reason.", "",
        "## The eval case", "",
        (f"`{EVALS_DIR}/{case}` is the eval case for this step. Check that it shows this failure, and extend it if it "
         "does not: the case was chosen by the step, not by what this session did. The edit is kept only if the case "
         "improves with it: run it with and without the proposed file, and keep the edit only when the comparison improves."
         if case else
         "No eval case shows this failure. Write one first (the incident-to-eval skill): until a case shows the failure, "
         "and improves when run with the edit and not without, the edit is not kept."), "",
        "## What to do with it", "",
        "`SKILL.md` beside this page is the proposed file and `SKILL.diff` its difference from the file the session used. "
        "Nothing in any repository was changed. An edit enters the skill as a change of its own, with its record.", ""])
