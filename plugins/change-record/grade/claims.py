"""claims: what the two measures claim about a session, a person's rulings on those claims, and
each measure's error (record docs/changes/2026-11-15-checkable-judges.md, R4 and R5).

A measure's answer is a list of claims, each with an id made from its content: a pair of quotes
that say one point twice (repeats.py), a defect a script shows (review.py). Neither gives a
label or a pass rate. A person checks a measure claim by claim: in the session's label file,
`said-again: wrong <id>... | right <id>...` and `defects: wrong <id>... | right <id>...`
(labels.py reads them). A measure's error is its claims ruled wrong over its claims ruled, and
under MIN_RULED ruled claims it is not yet checked.

A ruling applies to whichever counted answer of the session holds its id, a review's from either
model. One on an id no counted answer holds (the session was asked again and answered
differently, the review looked outside its clone, the id is mistyped) is stale: listed, and
counted for nothing.

answers: {"repeats": {sessionId: document}, "reviews": {sessionId: {model: document}}}, as the
two commands leave them in DIR/repeats and DIR/reviews. A document that is not what a measure
writes is not counted; nothing here trusts its shape.
"""
import review

MIN_RULED = 10  # ruled claims before a measure's error is printed: twice the five sessions a step asks for (R5)
SAID, SHOWN = "said-again", "defects"
WORDS = {SAID: ("pairs", "pair"), SHOWN: ("defects", "defect")}
INTRO = {
    SAID: "How much of a session's closing message says a point a second time, as Claude Sonnet took the message apart "
          "(`transcripts judge --repeats`). A pair is counted only when both of its quotes are in the message and differ. "
          "It is a count, with no label and no pass rate.",
    SHOWN: "The defects a reviewer that runs the code could show in a session's own commits (`transcripts judge --review`): "
           "each is a script that exits 0 at the session's last commit and not at its base. The count is a floor: a reviewer "
           "shows different defects on different runs, so none shown is weak evidence of none. Changed lines are the lines "
           "added plus the lines removed between the base and the last commit, binary files left out. No label and no pass rate.",
}
STALE = ("No counted answer here for the session holds the id: it was asked again and answered differently, or the id is "
         "not the sheet's.")


def whole(v):
    return v if isinstance(v, int) and not isinstance(v, bool) and v >= 0 else None


def said(doc):
    """The pairs of a counted repeats answer by id, or None when the document is not one."""
    if not (isinstance(doc, dict) and doc.get("status") == "counted" and whole(doc.get("points")) is not None
            and isinstance(doc.get("pairs"), list)):
        return None
    return {p["id"]: p for p in doc["pairs"] if isinstance(p, dict) and isinstance(p.get("id"), str)}


def shown(doc):
    """The shown defects of a counted review by id, or None when the document is not one."""
    if not (isinstance(doc, dict) and doc.get("status") == "reviewed" and isinstance(doc.get("defects"), list)):
        return None
    return {d["id"]: d for d in doc["defects"]
            if isinstance(d, dict) and d.get("status") == review.SHOWN and isinstance(d.get("id"), str)}


def reviews(answers, sid):
    """[(model, document)] a session has, Sonnet's first."""
    mine = (answers.get("reviews") or {}).get(sid) or {}
    return [(m, mine[m]) for m in list(review.MODELS) + sorted(set(mine) - set(review.MODELS)) if m in mine]


def held(answers, sid):
    """{SAID: {id: pair}, SHOWN: {id: (model, defect)}}: the claims a session's counted answers hold."""
    defects = {}
    for model, doc in reviews(answers, sid):
        for i, d in (shown(doc) or {}).items():
            defects.setdefault(i, (model, d))
    return {SAID: said((answers.get("repeats") or {}).get(sid)) or {}, SHOWN: defects}


def ruled(answers, labels, line):
    """(claims ruled, ruled wrong, [(sessionId, [id])] ruled wrong, [(sessionId, [id])] stale) for one measure."""
    n = wrong = 0
    wrongs, stale = [], []
    for sid in sorted(labels):
        mine, here = (labels[sid].get("claims") or {}).get(line) or {}, held(answers, sid)[line]
        bad = [i for i in mine.get("wrong") or [] if i in here]
        gone = [i for i in (mine.get("wrong") or []) + (mine.get("right") or []) if i not in here]
        n += len(bad) + sum(1 for i in mine.get("right") or [] if i in here)
        wrong += len(bad)
        wrongs += [(sid, bad)] if bad else []
        stale += [(sid, gone)] if gone else []
    return n, wrong, wrongs, stale


def error_lines(answers, labels, line):
    n, wrong, wrongs, stale = ruled(answers, labels, line)
    many, one = WORDS[line]
    err = (f"{round(100 * wrong / n)}% ({wrong} of {n} ruled {many} wrong)" if n >= MIN_RULED
           else f"not yet checked ({n} of {MIN_RULED} ruled {many} needed)")

    def ids(found):
        return "; ".join(f"{sid[:8]} " + " ".join(f"`{i}`" for i in got) for sid, got in found)
    out = ["", f"Its error: {err}. A person rules a {one} by the id the session's sheet shows, in the session's label file: "
               f"`{line}: wrong <id>... | right <id>...`; under {MIN_RULED} ruled, the measure is not yet checked."]
    if wrongs:
        out += ["", f"Ruled wrong: {ids(wrongs)}."]
    if stale:
        out += ["", f"Stale rulings, not counted: {ids(stale)}. {STALE}"]
    return out


def why_not(doc, red):
    """Why a document is not counted, in a few words."""
    if not isinstance(doc, dict):
        return "not an answer"
    status = doc.get("status") if isinstance(doc.get("status"), str) else "no status"
    status = "not what the measure writes" if status in ("counted", "reviewed") else status
    return red(status + (f": {doc['detail']}" if isinstance(doc.get("detail"), str) and doc["detail"] else ""))


def kinds(defects):
    named = [d for d in defects if d.get("named")]
    out = [f"{sum(1 for d in named if d.get('kind') == k)} {k}" for k in review.KINDS if any(d.get("kind") == k for d in named)]
    rest = len(defects) - sum(1 for d in named if d.get("kind") in review.KINDS)
    return ", ".join(out + ([f"{rest} not named in the answer"] if rest else [])) or "none"


def sections(answers, labels, groups, label, red):
    """The report's two sections. groups: [((skill, blob), [sessionId])] in the report's order, every
    session of the report in one; label(skill, blob): a version's heading."""
    everyone = [s for _, sids in groups for s in sids]
    stray = sorted((set(answers.get("repeats") or {}) | set(answers.get("reviews") or {})) - set(everyone))
    groups = list(groups) + ([(None, stray)] if stray else [])
    total = len(everyone) + len(stray)

    def head(key):
        return "### " + (label(*key) if key else "Sessions with no index entry and no score row here")

    def have(n, what):
        return (f"{n} of {total} sessions here have a counted {what}." if n else f"No session here has a counted {what}.")

    docs = answers.get("repeats") or {}
    good = {s: d for s, d in docs.items() if said(d) is not None}
    out = ["", "## Said again", "", f"{INTRO[SAID]} {have(len(good), 'answer')}"]
    for key, sids in groups:
        mine = [s for s in sids if s in good]
        if not mine:
            continue
        def row(name, points, pairs):
            return f"| {name} | {points} | {pairs} | {f'{pairs / points:.2f}' if points else '-'} |"
        out += ["", head(key), "", "| Session | Points | Said again | Share |", "|---|---|---|---|"]
        out += [row(s[:8], good[s]["points"], len(said(good[s]))) for s in mine]
        if len(mine) > 1:
            out.append(row(f"Together ({len(mine)})", sum(good[s]["points"] for s in mine), sum(len(said(good[s])) for s in mine)))
    bad = [f"{s[:8]} ({why_not(docs[s], red)})" for s in sorted(docs) if s not in good]
    out += (["", f"Not counted: {'; '.join(bad)}."] if bad else []) + error_lines(answers, labels, SAID)

    revs = {s: reviews(answers, s) for s in sorted(answers.get("reviews") or {})}
    good = {s: [(m, d) for m, d in got if shown(d) is not None] for s, got in revs.items()}
    out += ["", "## Defects shown", "", f"{INTRO[SHOWN]} {have(sum(1 for got in good.values() if got), 'review')}"]
    for key, sids in groups:
        rows = [(s, m, d) for s in sids for m, d in good.get(s) or []]
        if not rows:
            continue
        def row(name, model, lines, defects):
            rate = f"{1000 * len(defects) / lines:.1f}" if lines else "-"
            return f"| {name} | {red(model)} | {'unknown' if lines is None else lines} | {len(defects)} | {rate} | {kinds(defects)} |"
        out += ["", head(key), "", "| Session | Reviewer | Changed lines | Defects shown | Per 1,000 lines | Kinds |", "|---|---|---|---|---|---|"]
        out += [row(s[:8], m, whole(d.get("changed_lines")), list(shown(d).values())) for s, m, d in rows]
        for model in dict.fromkeys(m for _, m, _ in rows):
            mine = [d for _, m, d in rows if m == model]
            if len(mine) > 1:
                lines = [whole(d.get("changed_lines")) for d in mine]
                out.append(row(f"Together ({len(mine)})", model, None if None in lines else sum(lines),
                               [x for d in mine for x in shown(d).values()]))
    bad = [f"{s[:8]} {red(m)} ({why_not(d, red)})" for s, got in revs.items() for m, d in got if shown(d) is None]
    return out + (["", f"Not counted: {'; '.join(bad)}."] if bad else []) + error_lines(answers, labels, SHOWN)


def sheet_lines(sid, answers, red, width=400):
    """The sheet's last section: a session's claims with their ids, for a person to rule. [] when it has none."""
    mine = held(answers, sid)

    def cut(v):
        text = " ".join(red(v if isinstance(v, str) else "").split())  # redacted first: a cut can halve a secret
        return text if len(text) <= width else text[:width] + " [...]"
    if not (mine[SAID] or mine[SHOWN]):
        return []
    out = ["## Claims to rule", "",
           "What follows is not what the session did. It is what two measures claim about it, for you to check claim by "
           f"claim. In the label file write `{SAID}: wrong <id>... | right <id>...` for the pairs and "
           f"`{SHOWN}: wrong <id>... | right <id>...` for the defects, with the ids below; leave out a claim you did not check.", ""]
    if mine[SAID]:
        out += ["### Said again", "",
                "Each pair is two passages of the session's last message that a model took for one point said twice. It is "
                "right when both tell the reader the same thing, and wrong when the second says something the first does not.", ""]
        out += [f"- `{i}`: \"{cut(p.get('first'))}\" and again \"{cut(p.get('again'))}\"" for i, p in mine[SAID].items()] + [""]
    if mine[SHOWN]:
        out += ["### Defects shown", "",
                "Each is a script a reviewer left, which exits 0 at the session's last commit and not at its base. It is right "
                "when what it shows is a defect of the session's change, and wrong when it is not: the script tests something "
                "the change never promised, or passes for a reason that is not the one given. The paths are under the folder "
                "the sheets are in.", ""]
        for i, (model, d) in mine[SHOWN].items():
            kind = d.get("kind") if d.get("kind") in review.KINDS else "other"
            where = f", in {cut(d.get('file'))}" if d.get("file") else ""
            name = cut(d.get("script"))
            out += [f"- `{i}` ({red(model)}, {kind}{where}): {cut(d.get('what')) or 'the reviewer did not name it in its answer'}"
                    + (f" It breaks: {cut(d.get('guarantee'))}" if d.get("guarantee") else "")
                    + f" Script: `reviews/{sid}/{red(model)}/scripts/{name}`; what it printed at the last commit: "
                      f"`reviews/{sid}/{red(model)}/runs/{name}.last.out`."]
        out.append("")
    return out
