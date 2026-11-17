#!/bin/bash
# Both arms get the same project rules; global helpers are not installed.
set -euo pipefail
case_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$case_dir/../wrong-finding/scaffold.sh"
cat > CLAUDE.md <<'MD'
# Evaluation environment

If a named skill or helper is unavailable, follow the applicable written rules directly;
do not pretend to invoke it, install it, or stop solely because it is absent.
Only invoke skills that are present in the session's available skill list.
The canonical working rules below apply to this project. Global installer helpers are
not installed in this isolated evaluation environment.

MD
cat "$case_dir/../../AGENT-WORKFLOW.md" >> CLAUDE.md
git add CLAUDE.md
git -c user.name=Owner -c user.email=owner@example.com -c commit.gpgsign=false commit -q -m "test: supply shared working rules"
