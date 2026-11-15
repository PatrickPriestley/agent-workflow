You are reviewing a change in this repository: the commits @BASE@..@HEAD@. @HEAD@ is checked out;
`git diff @BASE@ @HEAD@` is the change and `git log @BASE@..@HEAD@` its commits.

Review the code and its tests the way a careful senior reviewer would. Unlike a reader of a
diff you can run it: this is a scratch clone, you may run anything in it and write scratch
files (do not commit). Find defects by trying the code: unusual inputs, error paths, the
guarantees its comments, tests and documentation claim. Judge code and tests, not the process
that produced them, and not documentation except where it contradicts the code.

Method, all of it required:

1. Read every changed code file in full, not only the diff, and the tests that came with it.
2. For each thing the change adds that is called from outside (a command, an option, a
   function other code calls), write down the guarantees it states: in its docstring, its
   comments, its usage text, the names of its tests, the README.
3. For each guarantee, try to break it with inputs the tests do not use. Look at what the
   tests feed the code, then feed it something else: nested where they are flat, empty,
   very long, the wrong type, hostile content inside otherwise valid input, a second run
   after a first, a failure half way.
4. Do not stop before you have run at least 15 such experiments. A guarantee you could not
   break after two honest tries is fine; say so and move on.

Defects. Report a defect only if you reproduced it, and leave the reproduction as a
script: `.review/defect-1.sh`, `.review/defect-2.sh`, and so on, in this clone. Each script
is run with bash from the repository's root, in a fresh clone of the same commit, with
nothing else of yours there: it makes its own inputs in a folder from `mktemp -d`, runs the
repository's code, prints what it saw, and exits 0 if and only if it saw the defect (exit 1
when the code behaves correctly). It must not pass by default: on a commit where the defect
is fixed, or where the code does not exist, it exits 1. Run each script yourself before you
report it. A suspicion you could not turn into such a script goes under "unverified".

End with a last message that is one JSON object and nothing else:
{"defects": [{"script": ".review/defect-1.sh", "file": "path", "kind": "wrong result" or "crash" or "data lost or leaked" or "stated guarantee broken" or "test cannot fail" or "other", "what": "one or two sentences", "guarantee": "where the code or its documents promise otherwise, quoted, or null"}],
 "unverified": ["..."],
 "experiments": ["one line each: what you tried and what happened"]}
