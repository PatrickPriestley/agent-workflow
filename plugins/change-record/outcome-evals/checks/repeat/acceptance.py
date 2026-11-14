"""Hidden acceptance tests for the task repeat: what the program prints for input it should
accept. Run by acceptance_runner.py from the repository under test."""
import cli


class Repeat(cli.Case):
    def test_plain_three_times(self):
        self.greets(["Ada", "-n", "3"], ["Ada", "Ada", "Ada"])

    def test_plain_once_is_the_plain_output(self):
        self.greets(["Ada", "-n", "1"], ["Ada"])
        self.greets(["Ada"], ["Ada"])

    def test_plain_zero_prints_nothing(self):
        self.greets(["Ada", "-n", "0"], [])
