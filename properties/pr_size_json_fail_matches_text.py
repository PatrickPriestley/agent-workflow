"""Properties of bin/pr-size's --fail with --json (https://hegel.dev).

  python3 properties/pr_size_json_fail_matches_text.py   # needs: pip install hegeltest==0.5.1

For arbitrary reviewable line counts and stop limits, `pr-size --fail` and
`pr-size --json --fail` must exit 1 exactly when the reviewable count is
above the stop limit, and 0 otherwise -- --json must not change the exit
code contract that --fail relies on.

Proposed by Property Scout; held on 087e13f (25 cases).
"""
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


def build(d, reviewable_lines):
    git(d, "init", "-q", "-b", "main")
    open(os.path.join(d, ".keep"), "w").close()
    git(d, "add", "-A")
    git(d, "commit", "-qm", "base")
    git(d, "checkout", "-qb", "feature")
    with open(os.path.join(d, "app.py"), "w") as f:
        f.write("".join(f"line {i}\n" for i in range(reviewable_lines)))
    git(d, "add", "-A")
    git(d, "commit", "-qm", "change")


def rc(d, *extra):
    return subprocess.run(["bash", PR_SIZE, "--fail", *extra], cwd=d, capture_output=True).returncode


@hegel.test(test_cases=25)
def test_fail_matches_with_json(tc):
    stop = tc.draw(gs.integers(1, 60))
    aim = tc.draw(gs.integers(1, stop))
    reviewable_lines = tc.draw(gs.integers(1, stop + 60))

    with tempfile.TemporaryDirectory() as d:
        build(d, reviewable_lines)
        text_rc = rc(d, "--aim", str(aim), "--stop", str(stop))
        json_rc = rc(d, "--json", "--aim", str(aim), "--stop", str(stop))

    assert text_rc == json_rc, (text_rc, json_rc, reviewable_lines, aim, stop)
    want = 1 if reviewable_lines > stop else 0
    assert text_rc == want, (text_rc, want, reviewable_lines, stop)


if __name__ == "__main__":
    test_fail_matches_with_json()
    print("pr_size_json_fail_matches_text: properties held")
