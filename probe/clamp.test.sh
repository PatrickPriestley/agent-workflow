#!/usr/bin/env bash
# Throwaway test for probe/clamp.sh. Covers the upper bound only, on purpose.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1: want [$3] got [$2]"; fi; }
check "150 is clamped to 100" "$(bash "$here/clamp.sh" 150 2>&1)" "100"
check "50 is unchanged" "$(bash "$here/clamp.sh" 50 2>&1)" "50"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
