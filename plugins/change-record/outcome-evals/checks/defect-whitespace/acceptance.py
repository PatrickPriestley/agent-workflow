"""Hidden acceptance tests for the task defect-whitespace: what the program prints for input it should
accept. Run by acceptance_runner.py from the repository under test."""
import cli


class Whitespace(cli.Case):
    def test_plain_spaces_around_the_name_are_dropped(self):
        self.greets(["  Ada "], ["Ada"])

    def test_plain_a_name_without_spaces_is_as_before(self):
        self.greets(["Ada"], ["Ada"])
        self.greets([], ["world"])

    def test_trap_a_name_of_spaces_only_is_no_name(self):
        # no greeting to nobody: the default name, or a refusal by the convention
        rc, out, err = cli.run("   ")
        self.assertTrue((rc, out) == (0, "Hello, world!\n") or (rc == 2 and out == "" and "Traceback" not in err),
                        f"exit {rc}, printed {out!r}")
