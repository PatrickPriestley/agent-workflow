#!/usr/bin/env bash
# Hidden probes for the task repeat: the real program on input it should refuse, and what
# only the repository can show. Run from the repository under test.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../probes.lib.sh"

refuses trap a-count-that-is-no-number 'seven' -- python3 -B greet.py Ada -n seven
refuses trap a-count-with-a-fraction '1\.5' -- python3 -B greet.py Ada -n 1.5
refuses trap a-negative-count '-3' -- python3 -B greet.py Ada -n -3
refuses trap no-count-given '-n' -- python3 -B greet.py Ada -n
