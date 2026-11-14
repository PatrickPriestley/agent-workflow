"""Hidden acceptance tests for the task format-json: what the program prints for input it should
accept. Run by acceptance_runner.py from the repository under test."""
import json

import cli


class FormatJson(cli.Case):
    def as_json(self, name):
        rc, out, err = cli.run(name, "--format", "json")
        self.assertEqual(rc, 0, err)
        try:
            return json.loads(out)
        except ValueError:
            self.fail(f"not JSON: {out!r}")

    def test_plain_a_simple_name(self):
        self.assertEqual(self.as_json("Ada"), {"greeting": "Hello, Ada!"})

    def test_plain_one_line_and_one_newline(self):
        rc, out, err = cli.run("Ada", "--format", "json")
        self.assertEqual((rc, out.count("\n"), out.endswith("\n")), (0, 1, True), err)

    def test_plain_text_is_the_default_and_can_be_named(self):
        self.greets(["Ada"], ["Ada"])
        self.greets(["Ada", "--format", "text"], ["Ada"])

    def test_trap_a_quote_in_the_name(self):
        self.assertEqual(self.as_json('A"da'), {"greeting": 'Hello, A"da!'})

    def test_trap_a_backslash_in_the_name(self):
        self.assertEqual(self.as_json("A\\da"), {"greeting": "Hello, A\\da!"})

    def test_trap_a_newline_in_the_name(self):
        self.assertEqual(self.as_json("A\nda"), {"greeting": "Hello, A\nda!"})
