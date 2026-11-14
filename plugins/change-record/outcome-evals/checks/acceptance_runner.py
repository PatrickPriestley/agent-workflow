"""acceptance_runner.py ACCEPTANCE.py: run each test of that file against the repository in
the current folder and print one line a test: `acceptance trap|plain NAME pass|fail`.
Exit 0 when every test ran, whatever it found; 2 when the file cannot be used."""
import importlib.util
import os
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def tests(suite):
    for t in suite:
        if isinstance(t, unittest.TestSuite):
            yield from tests(t)
        else:
            yield t


def main(argv):
    if len(argv) != 2:
        print("usage: acceptance_runner.py ACCEPTANCE.py", file=sys.stderr)
        return 2
    spec = importlib.util.spec_from_file_location("acceptance", argv[1])
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as e:  # a file that cannot be loaded has checked nothing
        print(f"acceptance_runner: cannot load {argv[1]}: {e}", file=sys.stderr)
        return 2
    found = sorted(tests(unittest.defaultTestLoader.loadTestsFromModule(mod)), key=lambda t: t._testMethodName)
    for t in found:
        kind, _, name = t._testMethodName[len("test_"):].partition("_")
        if kind not in ("trap", "plain") or not name:
            print(f"acceptance_runner: {t._testMethodName} is neither test_trap_ nor test_plain_", file=sys.stderr)
            return 2
        r = unittest.TestResult()
        t.run(r)
        ok = r.testsRun == 1 and r.wasSuccessful() and not r.skipped
        print("acceptance", kind, name.replace("_", "-"), "pass" if ok else "fail")
    if not found:
        print(f"acceptance_runner: {argv[1]} has no test", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
