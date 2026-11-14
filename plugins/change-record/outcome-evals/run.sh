#!/usr/bin/env bash
# run.sh: the outcome-evals harness. See run.py for what it does and its options.
exec python3 -B "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run.py" "$@"
