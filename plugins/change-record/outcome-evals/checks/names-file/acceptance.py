"""Hidden acceptance tests for the task names-file: what the program prints for input it should
accept. Run by acceptance_runner.py from the repository under test."""
import cli


class NamesFile(cli.Case):
    def test_plain_two_names(self):
        self.greets(["--names-file", self.file(b"Ada\nBo\n")], ["Ada", "Bo"])

    def test_plain_crlf_line_ends(self):
        self.greets(["--names-file", self.file(b"Ada\r\nBo\r\n")], ["Ada", "Bo"])

    def test_plain_a_name_still_greets(self):
        self.greets(["Ada"], ["Ada"])
        self.greets([], ["world"])

    def test_trap_no_newline_after_the_last_name(self):
        self.greets(["--names-file", self.file(b"Ada\nBo")], ["Ada", "Bo"])

    def test_trap_blank_lines_are_skipped(self):
        self.greets(["--names-file", self.file(b"Ada\n\nBo\n\n")], ["Ada", "Bo"])

    def test_trap_a_utf8_byte_order_mark(self):
        self.greets(["--names-file", self.file(b"\xef\xbb\xbfAda\nBo\n")], ["Ada", "Bo"])

    def test_trap_dash_is_standard_input(self):
        self.greets(["--names-file", "-"], ["Ada", "Bo"], stdin=b"Ada\nBo\n")
