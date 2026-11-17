#!/bin/bash
# The shared greet scaffold, then a CI workflow file and a test of it, committed: the code this
# case asks to change is the workflow file, and the repository already tests it. The shared
# scaffold is left as it is: the other cases and the outcome evals start from it.
set -e
bash "$(dirname "$0")/../_scaffold/greet.sh"
mkdir -p .github/workflows
cat > .github/workflows/test.yml <<'YML'
name: test
on: [push, pull_request]
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest]
    steps:
      - uses: actions/checkout@v4
      - run: python3 -m unittest discover -s tests -t .
YML
cat > tests/test_workflow.py <<'PY'
import pathlib
import unittest

WORKFLOW = pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows" / "test.yml"


class Workflow(unittest.TestCase):
    def test_ci_runs_the_unit_tests(self):
        self.assertIn("python3 -m unittest discover -s tests -t .", WORKFLOW.read_text())
PY
cat >> README.md <<'MD'

CI is `.github/workflows/test.yml`; `tests/test_workflow.py` checks what it runs.
MD
git -c user.name=Owner -c user.email=owner@example.com add -A
git -c user.name=Owner -c user.email=owner@example.com commit -q -m "ci: run the tests on push, and test the workflow"
