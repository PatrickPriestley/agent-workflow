#!/usr/bin/env bash
# Hidden probes for the task format-json: the real program on input it should refuse, and what
# only the repository can show. Run from the repository under test.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../probes.lib.sh"

refuses trap a-format-it-does-not-know 'xml' -- python3 -B greet.py Ada --format xml
refuses trap no-format-given 'format' -- python3 -B greet.py Ada --format
