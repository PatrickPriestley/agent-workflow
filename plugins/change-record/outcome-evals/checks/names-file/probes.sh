#!/usr/bin/env bash
# Hidden probes for the task names-file: the real program on input it should refuse, and what
# only the repository can show. Run from the repository under test.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../probes.lib.sh"

refuses trap a-file-that-is-not-there 'no-such-file-71\.txt|names-file' -- python3 -B greet.py --names-file no-such-file-71.txt
refuses trap a-folder-for-a-file 'docs|names-file' -- python3 -B greet.py --names-file docs
refuses trap no-path-given 'names-file' -- python3 -B greet.py --names-file
