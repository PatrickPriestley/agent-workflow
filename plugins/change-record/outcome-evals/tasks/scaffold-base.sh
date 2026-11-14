#!/usr/bin/env bash
# The scaffold every task starts from, built in the current folder: the greet CLI of the
# process evals (a tiny Python program with one passing test, in a repository that asks for
# change records), with the repository's conventions written into its README. The prompts
# do not repeat the conventions; an agent that reads the repository finds them.
set -e
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../../evals/_scaffold/greet.sh"
sed -i.bak 's/greating/greeting/' README.md && rm -f README.md.bak
cat >> README.md <<'MD'

## Conventions

- A usage error (a bad option value, a file that cannot be read) prints one line to standard
  error that names the input, and exits with status 2. No traceback.
- Where an option takes a file, `-` means standard input.
- Several greetings print one to a line.
MD
printf '__pycache__/\n' > .gitignore
git -c user.name=Owner -c user.email=owner@example.com add -A
git -c user.name=Owner -c user.email=owner@example.com commit -q --amend -m "greet: initial"
