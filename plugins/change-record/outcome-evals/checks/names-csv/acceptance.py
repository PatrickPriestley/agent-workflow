"""Hidden acceptance tests for the task names-csv: what the program prints for input it should
accept. Run by acceptance_runner.py from the repository under test."""
import cli


class NamesCsv(cli.Case):
    def test_plain_one_name(self):
        self.greets(["--names", "Ana"], ["Ana"])

    def test_plain_two_names(self):
        self.greets(["--names", "Ana,Bo"], ["Ana", "Bo"])

    def test_plain_names_outside_ascii(self):
        self.greets(["--names", "Zo\u00eb,Jos\u00e9"], ["Zo\u00eb", "Jos\u00e9"])

    def test_plain_a_name_still_greets(self):
        self.greets(["Ada"], ["Ada"])
        self.greets([], ["world"])

    def test_trap_spaces_around_names(self):
        self.greets(["--names", "Ana, Bo , Cy"], ["Ana", "Bo", "Cy"])

    def test_trap_an_empty_item_is_skipped(self):
        self.greets(["--names", "Ana,,Bo"], ["Ana", "Bo"])

    def test_trap_a_trailing_comma(self):
        self.greets(["--names", "Ana,Bo,"], ["Ana", "Bo"])
