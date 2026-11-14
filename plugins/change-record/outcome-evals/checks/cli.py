"""What the acceptance tests share. The program under test is greet.py in the current folder;
the tests only run it, as its user would, and never import it."""
import os
import subprocess
import sys
import tempfile
import unittest

ENV = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PYTHONIOENCODING="utf-8")


def run(*args, stdin=None):
    """(exit status, standard output, standard error) of `python3 greet.py ARGS`."""
    r = subprocess.run([sys.executable, "-B", "greet.py", *args], input=stdin, capture_output=True, env=ENV, timeout=20)
    return r.returncode, r.stdout.decode("utf-8", "replace"), r.stderr.decode("utf-8", "replace")


class Case(unittest.TestCase):
    """A test method is named test_trap_<what> or test_plain_<what>: a trap is what a
    happy-path implementation gets wrong, plain is what it gets right."""

    def file(self, data):
        """The path of a temporary file holding these bytes, outside the repository."""
        f = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
        f.write(data)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def greets(self, args, names, stdin=None):
        """`greet.py ARGS` exits 0 and prints one greeting a line for these names, no more."""
        rc, out, err = run(*args, stdin=stdin)
        self.assertEqual((rc, out), (0, "".join(f"Hello, {n}!\n" for n in names)), err)
