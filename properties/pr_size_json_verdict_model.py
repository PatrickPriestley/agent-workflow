"""Properties of bin/pr-size's --json verdict (https://hegel.dev).

  python3 properties/pr_size_json_verdict_model.py   # needs: pip install hegeltest==0.5.1

Whatever the reviewable count and the --aim/--stop values, --json's "verdict"
field must equal: "split" if reviewable > stop, "over" if reviewable > aim,
else "within" -- computed here independently of bin/pr-size's own wording,
rather than by re-parsing its text output.

Proposed by Property Scout; held on 087e13f (25 cases).
"""
import json
import os
import subprocess
import sys
import tempfile

import hegel
from hegel import generators as gs

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PR_SIZE = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else
                          os.environ.get("PR_SIZE", os.path.join(ROOT, "bin", "pr-size")))


def git(cwd, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=cwd,
                   check=True, capture_output=True)


def reviewable_json(reviewable_lines, aim, stop):
    """Build a branch that adds exactly `reviewable_lines` lines of source, run --json."""
    with tempfile.TemporaryDirectory() as d:
        git(d, "init", "-q", "-b", "main")
        open(os.path.join(d, ".keep"), "w").close()
        git(d, "add", "-A")
        git(d, "commit", "-qm", "base")
        git(d, "checkout", "-qb", "feature")
        with open(os.path.join(d, "app.py"), "w") as f:
            f.write("".join(f"line {i}\n" for i in range(reviewable_lines)))
        git(d, "add", "-A")
        git(d, "commit", "-qm", "change")
        out = subprocess.run(
            ["bash", PR_SIZE, "--json", "--aim", str(aim), "--stop", str(stop)],
            cwd=d, capture_output=True, text=True,
        )
        return json.loads(out.stdout)


@hegel.test(test_cases=25)
def test_verdict_matches_model(tc):
    aim = tc.draw(gs.integers(1, 60))
    stop = tc.draw(gs.integers(aim, aim + 60))
    reviewable_lines = tc.draw(gs.integers(1, aim + 80))

    data = reviewable_json(reviewable_lines, aim, stop)
    actual = data["reviewable"]
    if actual > stop:
        want = "split"
    elif actual > aim:
        want = "over"
    else:
        want = "within"
    assert data["verdict"] == want, (data, aim, stop)


if __name__ == "__main__":
    test_verdict_matches_model()
    print("pr_size_json_verdict_model: properties held")
