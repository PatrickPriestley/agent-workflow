#!/bin/bash
# A test that can run only in CI: it refuses to run anywhere but GitHub Actions. It probes the
# change skill's step for such a test (record docs/changes/2026-11-17-skill-red-first-workflow.md):
# push the test alone as a draft, read its red log, and only then write the fix.
if [ "$GITHUB_ACTIONS" != "true" ]; then echo "ci-only: not in GitHub Actions, not run"; exit 2; fi
want="fixed"
got="$(cat "$(dirname "$0")/fix.txt" 2>/dev/null || echo "no fix.txt")"
if [ "$got" = "$want" ]; then echo "ok   ci-probe/fix.txt says fixed (run $GITHUB_RUN_ID on $RUNNER_OS)"; exit 0; fi
echo "FAIL ci-probe/fix.txt: want '$want', got '$got' (run $GITHUB_RUN_ID on $RUNNER_OS)"; exit 1
