#!/bin/bash
# A tiny Python CLI with a passing unittest suite, committed on main.
set -e
mkdir -p tests
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
cat > tests/__init__.py <<'PY'
PY
cat > tests/test_greet.py <<'PY'
import unittest

from greet import greet


class Greet(unittest.TestCase):
    def test_greets_by_name(self):
        self.assertEqual(greet("Ada"), "Hello, Ada!")
PY
cat > README.md <<'MD'
# greet

`python3 greet.py NAME` prints a greeting. Tests: `python3 -m unittest discover -s tests -t .`
MD
git init -q -b main
git -c user.name=Owner -c user.email=owner@example.com add -A
git -c user.name=Owner -c user.email=owner@example.com -c commit.gpgsign=false commit -q -m "greet: initial"
