#!/usr/bin/env bash
# Throwaway: exercises the /verify reviewer. Prints $1 clamped to 0..100.
n="${1:?usage: clamp.sh <integer>}"
if [ "$n" -lt 0 ]; then n=0; fi
if [ "$n" -gt 100 ]; then n=100; fi
echo "$n"
