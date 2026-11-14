Add `--format FORMAT` to greet.py: `python3 greet.py NAME --format json` prints the greeting as
JSON, `{"greeting": "Hello, NAME!"}`; `--format text`, the default, prints it as it is today.

Use the change record id `2026-11-14-format-json`, that is `docs/changes/2026-11-14-format-json.md`. This
repository has no remote: do not push and do not open a pull request. Finish with your work
committed on a branch, and give the pull request body you would have opened as your last
message. The tests run with `python3 -m unittest discover -s tests -t .`.
