#!/bin/bash
# A tiny Python CLI with a passing unittest suite, committed on main, in a repository that has
# adopted change records (docs/changes/README.md and TEMPLATE.md from the plugin's templates).
set -e
mkdir -p tests docs/changes
cat > greet.py <<'PY'
import sys


def greet(name):
    return f"Hello, {name}!"


def main(argv):
    name = argv[1] if len(argv) > 1 else "world"
    print(greet(name))


if __name__ == "__main__":
    main(sys.argv)
PY
: > tests/__init__.py
cat > tests/test_greet.py <<'PY'
import unittest

from greet import greet


class Greet(unittest.TestCase):
    def test_greets_by_name(self):
        self.assertEqual(greet("Ada"), "Hello, Ada!")
PY
cat > README.md <<'MD'
# greet

`python3 greet.py NAME` prints a greating. Tests: `python3 -m unittest discover -s tests -t .`
MD
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$here/../../templates/docs-changes/README.md" docs/changes/README.md
cp "$here/../../templates/docs-changes/TEMPLATE.md" docs/changes/TEMPLATE.md
git init -q -b main
git -c user.name=Owner -c user.email=owner@example.com add -A
git -c user.name=Owner -c user.email=owner@example.com -c commit.gpgsign=false commit -q -m "greet: initial"
