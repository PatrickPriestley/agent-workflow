#!/usr/bin/env bash
# Tests for the reusable workflows (docs/reusable-workflows.md): seven plain workflows other
# repositories call. Each must declare, under workflow_call, every input and secret it reads (a
# caller's are not seen otherwise), check out only this repository's tools, and the guide's
# example callers must call them with declared inputs and secrets only.
#   bash bin/reusable-workflows.test.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; root="$(cd "$here/.." && pwd)"
pass=0; fail=0; CURRENT=""
it() { CURRENT="$1"; }
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$CURRENT"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; }
assert_eq() { [ "$1" = "$2" ] && ok || bad "expected [$1] got [$2]"; }
SHARED="probe-report agent-sessions probe-ci-fix probe-score probe-score-auto probe-sweep refusal-improve"

check() {  # python3 check over the workflows and the guide; prints one line per problem
  python3 -I - "$root" "$1" $SHARED <<'PY'
import re, sys
root, what, names = sys.argv[1], sys.argv[2], sys.argv[3:]

def section(lines, start, indent):
    """The lines under lines[start], up to the next line indented `indent` or less."""
    out = []
    for l in lines[start + 1:]:
        if l.strip() and not l.lstrip().startswith("#") and len(l) - len(l.lstrip()) <= indent:
            break
        out.append(l)
    return out

def keys(lines, indent):
    return [m.group(1) for l in lines if (m := re.match(" " * indent + r"([A-Za-z0-9_-]+):", l))]

def declared(text):
    """workflow_call's inputs (name -> required) and secrets, from a workflow file."""
    lines = text.split("\n")
    at = [i for i, l in enumerate(lines) if l.rstrip().split("#")[0].rstrip() == "  workflow_call:"]
    if not at:
        return None, None
    call = section(lines, at[0], 2)
    inputs, secrets = {}, set()
    for i, l in enumerate(call):
        if l.rstrip() == "    inputs:":
            body = section(call, i, 4)
            for j, b in enumerate(body):
                if m := re.match(r"      ([A-Za-z0-9_-]+):", b):
                    inputs[m.group(1)] = any(x.strip() == "required: true" for x in section(body, j, 6))
        if l.rstrip() == "    secrets:":
            secrets = set(keys(section(call, i, 4), 6))
    return inputs, secrets

wf = {n: open(f"{root}/.github/workflows/{n}.yml").read() for n in names}
EDITS_CALLER = {"refusal-improve"}  # checks out the caller too, to edit its agents' prompts
problems = []
if what == "workflows":
    for n, text in wf.items():
        inputs, secrets = declared(text)
        if inputs is None:
            problems.append(f"{n}: no workflow_call"); continue
        body = "\n".join(l for l in text.split("\n") if not l.lstrip().startswith("#"))
        for s in sorted(set(re.findall(r"secrets\.([A-Za-z0-9_]+)", body)) - secrets):
            problems.append(f"{n}: reads secret {s} but workflow_call does not declare it")
        for i in sorted(set(re.findall(r"inputs\.([A-Za-z0-9_-]+)", body)) - set(inputs)):
            problems.append(f"{n}: reads input {i} but workflow_call does not declare it")
        checkouts = body.count("actions/checkout@") - (n in EDITS_CALLER)  # its own first checkout is the caller
        tools = body.count("repository: ${{ inputs.tools-repository || 'PatrickPriestley/agent-workflow' }}")
        refs = body.count("ref: ${{ inputs.tools-ref || 'main' }}")
        if not (checkouts == tools == refs) or body.count("persist-credentials: false") < checkouts + (n in EDITS_CALLER):
            problems.append(f"{n}: a checkout that is not this repository's tools, or keeps credentials")
        if checkouts and not {"tools-repository", "tools-ref"} <= set(inputs):
            problems.append(f"{n}: checks out tools but takes no tools-repository and tools-ref")
elif what == "callers":
    guide = open(f"{root}/docs/reusable-workflows.md").read()
    seen = []
    for block in re.findall(r"```yaml\n(.*?)```", guide, re.S):
        m = re.search(r"uses: PatrickPriestley/agent-workflow/\.github/workflows/([a-z-]+)\.yml@main", block)
        if not m or m.group(1) not in wf:
            problems.append("a caller that calls none of the shared workflows"); continue
        n = m.group(1); seen.append(n)
        inputs, secrets = declared(wf[n])
        lines = block.split("\n")
        job = [i for i, l in enumerate(lines) if "uses: PatrickPriestley" in l][0]
        passed_in, passed_sec = [], []
        for i, l in enumerate(lines):
            if l.rstrip() == "    with:" and i > job:
                passed_in = keys(section(lines, i, 4), 6)
            if l.rstrip() == "    secrets:" and i > job:
                passed_sec = keys(section(lines, i, 4), 6)
        for k in passed_in:
            if k not in inputs:
                problems.append(f"{n}'s caller passes input {k}, which it does not declare")
        for k in passed_sec:
            if k not in secrets:
                problems.append(f"{n}'s caller passes secret {k}, which it does not declare")
        for k, req in inputs.items():
            if req and k not in passed_in:
                problems.append(f"{n}'s caller leaves out required input {k}")
        if n == "probe-score" and "run-name: probe-score #${{ inputs.pr }}" not in block:
            problems.append("probe-score's caller does not keep the run name bin/probe-ready looks for")
    if sorted(seen) != sorted(names):
        problems.append(f"the guide has callers for {sorted(seen)}, not one for each of {sorted(names)}")
print("\n".join(problems))
PY
}

it "each shared workflow declares, under workflow_call, every input and secret it reads, and checks out only the tools"
assert_eq "" "$(check workflows)"
it "the guide has one caller per shared workflow, passing only declared inputs and secrets, and every required input"
assert_eq "" "$(check callers)"

it "the check finds what it is for"
T="$(mktemp -d "${TMPDIR:-/tmp}/reusable.XXXXXX")"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
cp -R "$root/.github" "$root/docs" "$T/" 2>/dev/null; real="$root"; root="$T"
mutate() {  # file old new -> the check's output on the mutant; restores the file after
  cp "$T/$1" "$T/orig"; python3 -I -c '
import sys; p, a, b = sys.argv[1:]; s = open(p).read(); assert a in s, a; open(p, "w").write(s.replace(a, b, 1))' "$T/$1" "$2" "$3"
  out="$(check "$4")"; cp "$T/orig" "$T/$1"; printf '%s' "$out"
}
nl='
'
o="$(mutate .github/workflows/probe-report.yml "      AGENT_TRANSCRIPTS_INSERT_KEY:${nl}        required: false${nl}" "" workflows)"
case "$o" in *"reads secret AGENT_TRANSCRIPTS_INSERT_KEY"*) ok ;; *) bad "an undeclared secret passed: [$o]" ;; esac
o="$(mutate .github/workflows/probe-score.yml "        default: main${nl}" "        default: main${nl}      nothing:${nl}        type: string${nl}" workflows)"
assert_eq "" "$o"
o="$(mutate .github/workflows/probe-score.yml "if: inputs.close" "if: inputs.closed" workflows)"
case "$o" in *"reads input closed"*) ok ;; *) bad "an undeclared input passed: [$o]" ;; esac
o="$(mutate .github/workflows/agent-sessions.yml "ref: \${{ inputs.tools-ref || 'main' }}" "ref: \${{ github.event.workflow_run.head_sha }}" workflows)"
case "$o" in *"a checkout that is not this repository's tools"*) ok ;; *) bad "a checkout of the run's code passed: [$o]" ;; esac
o="$(mutate docs/reusable-workflows.md "      pr: \${{ inputs.pr }}${nl}" "" callers)"
case "$o" in *"leaves out required input pr"*) ok ;; *) bad "a missing required input passed: [$o]" ;; esac
o="$(mutate docs/reusable-workflows.md "      PROBE_TOKEN: \${{ secrets.PROBE_TOKEN }}" "      PROBE_TOKN: \${{ secrets.PROBE_TOKEN }}" callers)"
case "$o" in *"passes secret PROBE_TOKN"*) ok ;; *) bad "an undeclared secret passed: [$o]" ;; esac
o="$(mutate docs/reusable-workflows.md "run-name: probe-score #" "run-name: score #" callers)"
case "$o" in *"run name"*) ok ;; *) bad "a lost run name passed: [$o]" ;; esac
o="$(mutate docs/reusable-workflows.md "workflows/probe-score-auto.yml@main" "workflows/probe-score-autos.yml@main" callers)"
case "$o" in *"calls none of the shared"*) ok ;; *) bad "a wrong workflow passed: [$o]" ;; esac
root="$real"

it "this test runs in CI"
grep -qF 'bash bin/reusable-workflows.test.sh' "$root/.github/workflows/test.yml" && ok || bad "not in test.yml"

echo; echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
