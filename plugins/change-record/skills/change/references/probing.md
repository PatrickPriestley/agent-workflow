# Probing and evidence labels

Memory and cached docs have been wrong about exit codes, flags and event lists. Try a tool,
API or command in a scratch directory before relying on how it behaves, a few lines each,
and write the result into the record's Probed facts.

## Labels

Every claim about another system carries one label, and changes label only on new evidence:

- **verified against the real system**: you sent the exact request to the version you target
  and saw the outcome you need.
- **exact source**: you read the receiver's own validation and dispatch code, in the exact
  version used, and it accepts what you send.
- **mock only**: a fake or stub accepted it. This proves your side, not the receiver's.
- **assumed**: from memory, a doc, a second parser or an example. Say so.

## The real-contract gate

Before building on a new call to another system (an API method, CLI, protocol message, file
format or device): send the exact request to the version you target, in a disposable
environment if it has to be started, and see the smallest outcome you need. Tests against a
fake, a doc, or a parser that lists the value do not pass the gate. A fake that accepts
everything proves nothing about the receiver. If you cannot run it, trace the receiver's own
validation in its exact source and label the fact `exact source`. Until the gate passes, the
work is a prototype and the record says so.

## Impossible requests

If a probe shows the request impossible or resting on something false (a command that does
not exist, a value the receiver rejects, a behaviour the library does not have), stop and
report it with the probe's output. Never build the nearest thing instead: that is a scope
change, and the owner decides it.
