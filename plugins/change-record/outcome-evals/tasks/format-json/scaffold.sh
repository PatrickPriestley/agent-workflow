#!/usr/bin/env bash
# Builds this task's repository in the current folder. Every task starts from the same one.
set -e
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scaffold-base.sh"
