"""Properties of bin/pr-size, checked with Hegel (https://hegel.dev).

  python3 properties/pr_size.py [PATH-TO-PR-SIZE]   # needs: pip install hegeltest==0.5.1

Lockfiles never count as reviewable lines, whatever other files a change adds
and at whatever depth the lockfiles sit. Each generated case builds a small git
repository, commits the files on a branch and reads pr-size's count.

Red: on probe #22's bin/pr-size (020b96f, package-lock.json dropped from the
excluded lockfiles) this fails, and Hegel shrinks it to one 1-line
package-lock.json with no other file.
"""
import os
import re
import subprocess
import sys
import tempfile

import hegel
from hegel import generators as gs

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The script under test: the first argument, else $PR_SIZE, else this checkout's.
PR_SIZE = (sys.argv[1] if len(sys.argv) > 1 else
           os.environ.get("PR_SIZE", os.path.join(ROOT, "bin", "pr-size")))
LOCKS = ["Cargo.lock", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "poetry.lock",
         "uv.lock", "Gemfile.lock", "go.sum", "composer.lock"]
SOURCES = ["app.py", "lib/util.sh", "src/main.go", "README.md"]


def git(cwd, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=cwd,
                   check=True, capture_output=True)


def reviewable(files):
    """pr-size's reviewable line count for a branch that adds `files` (path -> lines)."""
    with tempfile.TemporaryDirectory() as d:
        git(d, "init", "-q", "-b", "main")
        open(os.path.join(d, ".keep"), "w").close()
        git(d, "add", "-A")
        git(d, "commit", "-qm", "base")
        git(d, "checkout", "-qb", "feature")
        for path, n in files.items():
            full = os.path.join(d, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as f:
                f.write("".join(f"line {i}\n" for i in range(n)))
        git(d, "add", "-A")
        git(d, "commit", "-qm", "change")
        out = subprocess.run(["bash", PR_SIZE, "main..feature"], cwd=d, capture_output=True, text=True)
        m = re.search(r"(\d+) reviewable lines", out.stdout + out.stderr)
        assert m, out.stdout + out.stderr
        return int(m.group(1))


@hegel.test(test_cases=25)
def test_lockfiles_are_never_reviewable(tc):
    sources = tc.draw(gs.dicts(gs.sampled_from(SOURCES), gs.integers(1, 30)))
    locks = tc.draw(gs.dicts(gs.sampled_from(LOCKS), gs.integers(1, 30), min_size=1))
    nested = tc.draw(gs.booleans())
    files = dict(sources)
    files.update({("sub/" if nested else "") + k: v for k, v in locks.items()})
    assert reviewable(files) == sum(sources.values()), f"lockfiles counted: {locks}"


if __name__ == "__main__":
    test_lockfiles_are_never_reviewable()
    print("pr_size: properties held")
