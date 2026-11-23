# Review findings are claims

A review may run on the PR in CI (Open Code Review, PR-Agent with agent-workflow's review
skill, or your own), or locally before the push with
`agent-review code --goal "<the record's Goal>"`. Whichever ran:

- **Probe each finding** against the real code before acting on it. Run the input it
  describes. A wrong fix applied on trust ships a bug.
- **Critical or important** means wrong behaviour, lost data, a security hole or a bypassed
  safeguard, with a concrete case. When unsure, treat it as important.
- **Fix verified findings test-first**: the test that shows the finding, red, then the fix.
  `red-check` will see it, where it runs.
- **Dismiss a finding only with evidence**: a probe you ran, or code you cite, that shows it
  cannot happen. Write the evidence in your reply on the PR, not just "not an issue".
- **Carry minor findings** into the record's Outcome as open items, with your reason.
- **Re-push and re-review** until nothing critical or important remains, for at most two
  fix rounds. If findings remain after that, stop and report them with your evidence; a
  third rewrite is usually tests being reshaped to satisfy a reviewer, not a fix. A review
  that did not finish (cut off, no end marker, timed out) is not a review.
- **After any fix, run the real-use commands again** on the final code and replace the
  output in the record, so the record never quotes code that has since changed.

The review proves the reviewer finished, not that the change works. Step 5 of the loop
(use it as its user would) is what shows that.
