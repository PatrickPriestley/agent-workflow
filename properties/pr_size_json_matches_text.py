"""Properties of bin/pr-size's --json flag (https://hegel.dev).

  python3 properties/pr_size_json_matches_text.py   # needs: pip install hegeltest==0.5.1

--json must report the same facts as the plain text output, since both are
printed from the same counters in bin/pr-size, just in two different shapes.
For arbitrary mixes of source files, lockfiles and generated-dir files, and
arbitrary --aim/--stop values, reviewable, generated, aim, stop, range and
verdict must all agree between `pr-size` and `pr-size --json`.

Proposed by Property Scout; held on 087e13f (25 cases).
"""
import json
import os
import re
import subprocess
import sys
import tempfile

import hegel
from hegel import generators as gs

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PR_SIZE = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else
                          os.environ.get("PR_SIZE", os.path.join(ROOT, "bin", "pr-size")))
LOCKS = ["Cargo.lock", "package-lock.json", "yarn.lock"]
SOURCES = ["app.py", "lib/util.sh", "src/main.go"]
GENERATED = ["tests/fixtures/f.json", "pkg/testdata/t.txt"]


def git(cwd, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=cwd,
                   check=True, capture_output=True)


def run(cwd, *extra):
    return subprocess.run(["bash", PR_SIZE, *extra], cwd=cwd, capture_output=True, text=True).stdout


def build_repo(d, files):
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


@hegel.test(test_cases=25)
def test_json_matches_text(tc):
    sources = tc.draw(gs.dicts(gs.sampled_from(SOURCES), gs.integers(1, 30)))
    locks = tc.draw(gs.dicts(gs.sampled_from(LOCKS), gs.integers(1, 30)))
    generated = tc.draw(gs.dicts(gs.sampled_from(GENERATED), gs.integers(1, 30)))
    aim = tc.draw(gs.integers(1, 50))
    stop = tc.draw(gs.integers(aim, aim + 50))
    files = {**sources, **locks, **generated}
    tc.assume(bool(files))

    with tempfile.TemporaryDirectory() as d:
        build_repo(d, files)
        extra = ["--aim", str(aim), "--stop", str(stop)]
        text = run(d, *extra)
        js = run(d, "--json", *extra)

    data = json.loads(js)
    # The range is two hex abbreviations; a comma follows it when there are no generated files.
    m = re.search(r"(\d+) reviewable lines added in ([0-9a-f]+\.\.[0-9a-f]+)", text)
    assert m, text
    assert data["reviewable"] == int(m.group(1)), (data, text)
    assert data["range"] == m.group(2), (data, text)
    gm = re.search(r"\((\d+) more in generated files", text)
    assert data["generated"] == (int(gm.group(1)) if gm else 0), (data, text)
    assert data["aim"] == aim and data["stop"] == stop, (data, text)
    if "above the" in text:
        want = "split"
    elif "over the" in text:
        want = "over"
    else:
        want = "within"
    assert data["verdict"] == want, (data["verdict"], want, text)


if __name__ == "__main__":
    test_json_matches_text()
    print("pr_size_json_matches_text: properties held")
