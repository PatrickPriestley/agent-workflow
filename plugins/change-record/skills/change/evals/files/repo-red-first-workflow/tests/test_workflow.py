import pathlib
import unittest

WORKFLOW = pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows" / "test.yml"


class Workflow(unittest.TestCase):
    def test_ci_runs_the_unit_tests(self):
        self.assertIn("python3 -m unittest discover -s tests -t .", WORKFLOW.read_text())
