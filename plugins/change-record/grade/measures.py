"""measures: what a session took, counted from its transcript (record
docs/changes/2026-11-12-session-quality.md, R1 and R2).

Counts, not verdicts: nothing here says whether a number is too high. They are read from the
transcript's own lines, so they need no grader and no model, and they are computed when the
report runs and stored nowhere.

  * output_tokens: the `output_tokens` of each assistant message, once per message. One message
    is written on several lines (a line per block), each repeating the same usage, so adding
    line by line counts it several times. None when no line carries usage.
  * tool_calls, calls_not_ok: the session's calls, and those that failed or were refused, as
    the field graders read them (grade/fields.py).
  * messages, characters, last_message: the text the session wrote, and its last piece.
  * person_turns: messages a person typed, after the first. A line the harness wrote (isMeta), a
    compaction summary, and a notification or command wrapped in a tag are not a person.
  * minutes: from the first line's time to the last line's, waiting included.

Lines of subagents kept inline (isSidechain) are left out, as the graders leave them out.
"""
import json
import re
import statistics
from datetime import datetime

import fields

COUNTS = [  # (key, the summary's row, the session table's column)
    ("output_tokens", "Output tokens", "Output tokens"),
    ("tool_calls", "Tool calls", "Tool calls"),
    ("calls_not_ok", "Calls that failed or were refused", "Failed or refused"),
    ("messages", "Messages written", "Messages"),
    ("characters", "Characters written", "Characters"),
    ("last_message", "Characters in the last message", "Last message"),
    ("person_turns", "Turns from a person after the first", "Turns from a person"),
    ("minutes", "Minutes, first line to last", "Minutes"),
]
WRAPPED = re.compile(r"^<[a-z][a-z-]*>")  # <task-notification>, <command-name>, <system-reminder>: not typed by a person


def stamp(s):
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except ValueError:
        return None


def measure(lines):
    """The counts for one transcript's lines; raises fields.Unparsable on a line that is not JSON."""
    calls, texts, _ = fields.read(lines)
    tokens, seen, usage_found, people, times = 0, set(), False, 0, []
    for raw in lines:
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", "replace")
        if not raw.strip():
            continue
        d = json.loads(raw)
        if not isinstance(d, dict) or d.get("isSidechain"):
            continue
        t = stamp(d.get("timestamp")) if d.get("timestamp") else None
        if t:
            times.append(t)
        message = d.get("message") if isinstance(d.get("message"), dict) else {}
        if d.get("type") == "assistant":
            out = (message.get("usage") or {}).get("output_tokens")
            if isinstance(out, int):
                usage_found = True
                mid = message.get("id")
                if mid is None or mid not in seen:
                    tokens += out
                if mid is not None:
                    seen.add(mid)
        elif d.get("type") == "user" and not d.get("isMeta") and not d.get("isCompactSummary"):
            content = message.get("content")
            if isinstance(content, list):
                if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
                    continue
                content = "\n".join(b.get("text") or "" for b in content if isinstance(b, dict) and b.get("type") == "text")
            if isinstance(content, str) and content.strip() and not WRAPPED.match(content.strip()):
                people += 1
    written = [t for _, t in texts if t.strip()]
    return {
        "output_tokens": tokens if usage_found else None,
        "tool_calls": len(calls),
        "calls_not_ok": sum(1 for c in calls if c.status != "ran"),
        "messages": len(written),
        "characters": sum(len(t) for t in written),
        "last_message": len(written[-1]) if written else 0,
        "person_turns": max(0, people - 1),
        "minutes": (max(times) - min(times)).total_seconds() / 60 if times else None,
    }


def shown(value):
    """A count as the report prints it: whole numbers with thousands separated, else one decimal."""
    if value is None:
        return "-"
    r = round(value, 1)
    return f"{int(r):,}" if r == int(r) else f"{r:,.1f}"


def summary(by_session, name):
    """Rows of the summary table for one group: {sessionId: counts} -> [(row, sessions, middle, least, most)]."""
    out = []
    for key, row, _ in COUNTS:
        have = sorted((sid, m[key]) for sid, m in by_session.items() if m.get(key) is not None)
        if not have:
            out.append((row, 0, "-", "-", "-"))
            continue
        values = [v for _, v in have]
        least = min(have, key=lambda p: (p[1], p[0]))
        most = min(have, key=lambda p: (-p[1], p[0]))
        out.append((row, len(have), shown(statistics.median(values)),
                    f"{shown(least[1])} ({name(least[0])})", f"{shown(most[1])} ({name(most[0])})"))
    return out
