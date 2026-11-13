---
id: 2026-11-12-probe-no-content
tier: 1
status: done
requester: Patrick Priestley, in chat on 2026-11-12 ("Privacy and capture first", to the order of fixing the defects the labellers found: "1. The probe leak, before you run it")
approvers: []
---
# The probe does not copy the keys or values of a string that is itself JSON

## Goal

`transcripts probe` promises a sample with structure and no content, which the owner is to
commit from their own machine. A string that happens to be JSON is content: a prompt, a
file a command printed. Its key names and values must not reach the sample.

## Probed facts

- Exact source (`plugins/change-record/probe/agent_sample.py` on `main` at `5a815dc`,
  `Shape.add` and `json_in`): any string value that parses as a JSON object or array is
  descended into like a part of the transcript, to twelve levels. Its keys are written as key
  paths when they look like field names, and the values under `type`, `status`, `source`,
  `reason`, `model`, `kind` and the other `TYPE_KEYS` are kept when they look like
  identifiers.
- Verified against the real system (`bin/transcripts.test.sh` with this record's test, a
  made-up Codex rollout, in this container): with a prompt, a tool argument and a command's
  output that are JSON, the sample holds `accountOwner`, `password`, `customerName`,
  `dependencies`, `leftpad`, `deployTarget`, `billingPlan`, `clientList` as key names and
  `confidential`, `churned`, `enterprise`, `crm` as kept values. Twelve of thirteen made-up
  words; the thirteenth was a value under a key that keeps none.
- Exact source (`grade/fixtures/agents/made-up/codex-stop.expected.json`): two JSON strings
  are structure the sample is meant to show. A function call's `arguments` is a JSON string
  whose keys are the tool's parameter names (`command`, `workdir`, `timeout_ms`). A function
  call's `output` is a JSON string the agent wraps a result in (`output`, `metadata.exit_code`,
  `metadata.duration_seconds`); the exit code there is how a grader would tell a command
  failed.
- Found by a blind labeller reading session `172fe91d` for code quality (record
  `2026-11-12-session-quality`), who reproduced it; the session's last message said key
  names could leak and did not say values could.
- The owner has not run the probe on their machine yet, so no sample from a real session
  exists.

## Decisions

- Inside a JSON string, a key name is kept only where it is the agent's and not the
  session's: the first level of a tool call's argument string (the names in `ARG_KEYS`:
  `arguments`, `input`, `tool_input`, `args`, `parameters`), and the names in `WRAPPER_KEYS`,
  the words an agent's own wrapper around a result uses. Every other key is written `<key>`,
  with its type. Rejected: not descending at all, which loses the exit code and the
  argument names the record's graders need.
- No value is kept inside a JSON string, whatever its key.
- A JSON string inside a JSON string is counted as `json-string` and not opened. One level
  is the agent's wrapper; the next is what a tool read or a person typed.
- The marker counts stay: they count fixed phrases and hold none of the text.
- A wrapper key this list does not have shows as `<key>`, so the owner sees there is one and
  can add its name. Rejected: keeping any key that looks like a field name, which is the
  defect.
- Plain objects are as before: their key names are kept when they look like field names.
  That is the sample's stated contract, and a labeller did not fault it.

## Tasks

1. `probe/agent_sample.py`. Test: in `bin/transcripts.test.sh`, a made-up rollout whose
   prompt, tool argument and outputs are JSON; none of its words may be in the sample, and
   the wrapper's keys and the argument names must be. It fails today as Probed facts say.

## Checks

`bash plugins/change-record/bin/transcripts.test.sh`; the two stored summaries of the
made-up transcripts must not change. Real use is the made-up rollout: there is no real
Codex or Cursor session in this container. Error path: a JSON string nested twelve deep. The
reviewer should attack: a key in `WRAPPER_KEYS` that is also a word a person's file would
use, and a tool whose argument object nests the session's data.

## Outcome

Shipped: `probe/agent_sample.py` (`ARG_KEYS`, `WRAPPER_KEYS`, and the `inside` state of
`Shape.add`), and the README's paragraph on what a sample holds. `transcripts.test.sh` goes
from 250 assertions to 279. The two stored summaries of the made-up transcripts are byte for
byte what they were, so what the probe was built to show is still shown.

Red first: 17 of the first 25 new assertions failed on the old code; twelve of the thirteen
made-up words were in the sample, for instance

    FAIL a string that is itself JSON is content: its key names and values are not copied
         unexpected [customerName] in: {
         unexpected [churned] in: {
         unexpected [password] in: {

Use, on the made-up rollout whose prompt, argument and outputs are JSON: the sample holds
none of the seventeen made-up words, and still holds

    "payload.output|json.metadata.exit_code": "number:1"
    "payload.output|json.output": "json-string:1"
    "payload.arguments|json.command[]": "string:2"
    "payload.arguments|json.env.<key>": "string:1"
    "payload.content[].text|json.<key>": "string:3"

Guards: eight broken by hand, all eight failed the suite. The first run of them misled: the
suite, run from a copy of the plugin outside the repository, has six failures of its own,
so a count of six was no catch. Counted without those, two guards had survived (a list
inside JSON content lost the masking, and a value under `status` inside a call's arguments
was kept); each now has a test. A third was a condition the one above it already made
redundant, and is removed.

What the reviewer was asked to attack:

- A `WRAPPER_KEYS` word that a person's own file uses. Such a key (`content`, `text`,
  `result`, `error`, `output`, `metadata`) is written by name wherever it occurs in a JSON
  string. The words are generic and no value goes with them; the sample would say that a
  file has a `content` key and no more.
- A tool whose argument object nests the session's data. Below the first level of an
  argument string every key is `<key>`. In a plain argument object, not a string, key names
  are kept as before: that is the contract stated at the top of the module, and the README
  now tells the owner to read a sample before committing it.

Not done: nothing has run against a real Codex or Cursor session; the probe on the owner's
machine is still the owner's step.
