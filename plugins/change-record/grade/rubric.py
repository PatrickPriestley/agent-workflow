"""rubric: the two judged rubrics that were tried and taken out (record
docs/changes/2026-11-12-session-quality.md, R4, R5 and its concern C2).

  verbosity     asked of the messages a session wrote, of Claude Haiku. Against 14 labelled
                sessions it answered proportionate every time and was wrong on 3.
  code-quality  asked of the diff of what a session committed, of Claude Sonnet, three votes,
                no tools. Against 7 labelled sessions it was wrong on 4, each an approval
                where the label blocks for a defect the labeller reproduced by running the
                code. Both of its blocks named a real defect.

The record allows a judge one wrong in five and says one over that is taken out and not
tuned. Neither is asked or reported any more. What stays: the rubric texts in grade/rubrics/
(adapted from Skill Doctor's scorers, MIT), and the labels, which are what each was measured
against. A label file may still carry a line for either, and grade/labels.py still checks the
line against the rubric's labels, which is all this module is for.
"""
import os
import re

RETIRED = ["code-quality", "verbosity"]
HERE = os.path.dirname(os.path.realpath(__file__))


def labels_of(question):
    """The answers a rubric allowed, from the top block of its file."""
    raw = open(os.path.join(HERE, "rubrics", question + ".md"), encoding="utf-8").read()
    m = re.search(r"^labels: \[(.*)\]\s*$", raw[4:raw.index("\n---", 4)], re.M)
    return [w.strip() for w in m.group(1).split(",")]


LABELS = {q: labels_of(q) for q in RETIRED}
