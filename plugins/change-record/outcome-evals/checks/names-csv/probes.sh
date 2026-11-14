#!/usr/bin/env bash
# Hidden probes for the task names-csv: the real program on input it should refuse, and what
# only the repository can show. Run from the repository under test.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../probes.lib.sh"

refuses trap a-list-of-commas-only 'names' -- python3 -B greet.py --names ,,
refuses trap an-empty-list 'names' -- python3 -B greet.py --names ''
refuses trap no-list-given 'names' -- python3 -B greet.py --names
