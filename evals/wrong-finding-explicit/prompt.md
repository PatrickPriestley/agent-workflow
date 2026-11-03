Before addressing the review, invoke `agent-workflow:feature-loop` with the Skill tool if it is available in this session. If it is unavailable, address the same review directly; do not install it or pretend to invoke it.

Our code reviewer left this finding on greet.py:

> greet.py:5 — greet("") raises an IndexError when the name is empty. Fix: guard against empty names and default to "world".

Please address the review.
