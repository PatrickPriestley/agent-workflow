"""Check, inside the pinned PR-Agent image and with the workflow's settings, that the secret
ignore globs and the review skill take effect, before any diff reaches the model.

The workflow runs this with `docker run ... python /github/workspace/pr-agent/verify-image.py`
in the image's /app, with IGNORE__GLOB, SKILLS__ENABLED and SKILLS__PATHS passed through.
It fails if PR-Agent reads either list setting as something other than a list (a plain string
would make the globs match nothing, or the skill path point nowhere), if a sample secret path
survives PR-Agent's own filter, if an ordinary path is dropped, or if the workflow-review skill
is missing from PR-Agent's skills context. It also fails if PR-Agent's command line lacks a
flag pr-agent/try.sh passes, since README pins the local install to this image's version,
or if plain-diff mode (what try.sh runs) keeps a secret file or its contents when handed a
synthetic diff.
Exit 0 when all hold, 1 otherwise.
"""
import subprocess
import sys

from pr_agent.algo.file_filter import filter_ignored
from pr_agent.algo.skills_loader import get_skills_context
from pr_agent.config_loader import get_settings
from pr_agent.git_providers.plain_diff_provider import PlainDiffGitProvider

SECRETS = [".env", "config/.env.production", "keys/id_work", "home/.ssh/id_ed25519",
           "certs/server.pem", "deploy/TLS.KEY", "config/secrets.yml", "aws/credentials",
           "auth/token.go"]
ORDINARY = ["README.md", "src/main.rs", "docs/environment.md", "skills/feature-loop/SKILL.md"]
SKILL = "workflow-review"
CLI_FLAGS = ["--stdin", "--output", "--json-output"]  # what pr-agent/try.sh passes
CANARY = "SYNTHETIC_CANARY_VERIFY_IMAGE"
PLAIN_DIFF_SECRETS = [".env", "keys/id_work", "config/secrets.yml"]
PLAIN_DIFF_ORDINARY = "README.md"


def synthetic_diff(paths):
    """A unified diff adding each path with one line holding the canary."""
    return "".join(f"diff --git a/{p} b/{p}\nnew file mode 100644\nindex 0000000..1111111\n"
                   f"--- /dev/null\n+++ b/{p}\n@@ -0,0 +1 @@\n+API_KEY={CANARY}\n" for p in paths)


class ChangedFile:
    """What filter_ignored reads for the github platform: a .filename."""

    def __init__(self, filename):
        self.filename = filename


def main():
    problems = []
    settings = get_settings()
    for name, value in (("ignore.glob", settings.ignore.glob), ("skills.paths", settings.skills.paths)):
        if not isinstance(value, list):
            problems.append(f"{name} is a {type(value).__name__}, not a list: {value!r}")

    kept = {f.filename for f in filter_ignored([ChangedFile(p) for p in SECRETS + ORDINARY], "github")}
    leaked = [p for p in SECRETS if p in kept]
    dropped = [p for p in ORDINARY if p not in kept]
    if leaked:
        problems.append(f"secret paths not filtered: {', '.join(leaked)}")
    if dropped:
        problems.append(f"ordinary paths filtered: {', '.join(dropped)}")

    if SKILL not in get_skills_context():
        problems.append(f"the {SKILL} skill is not in PR-Agent's skills context")

    usage = subprocess.run([sys.executable, "-m", "pr_agent.cli", "--help"],
                           capture_output=True, text=True).stdout
    for flag in CLI_FLAGS:
        if flag not in usage:
            problems.append(f"PR-Agent's CLI lacks {flag}, which pr-agent/try.sh passes")

    settings.set("plain_diff.content", synthetic_diff(PLAIN_DIFF_SECRETS + [PLAIN_DIFF_ORDINARY]))
    plain = PlainDiffGitProvider().get_diff_files()
    plain_names = [f.filename for f in plain]
    kept_secrets = [p for p in PLAIN_DIFF_SECRETS if p in plain_names]
    if kept_secrets:
        problems.append(f"plain-diff mode kept secret paths: {', '.join(kept_secrets)}")
    if PLAIN_DIFF_ORDINARY not in plain_names:
        problems.append(f"plain-diff mode dropped {PLAIN_DIFF_ORDINARY}")
    leaked_into = [f.filename for f in plain if f.filename != PLAIN_DIFF_ORDINARY and CANARY in str(f.patch)]
    if leaked_into:
        problems.append(f"plain-diff mode kept the canary in: {', '.join(leaked_into)}")

    for problem in problems:
        print(f"verify-image: {problem}")
    if not problems:
        print(f"verify-image: ok: globs and skills paths are lists, {len(SECRETS)} secret paths "
              f"filtered, {len(ORDINARY)} ordinary paths kept, {SKILL} loaded, CLI has "
              f"{' '.join(CLI_FLAGS)}, plain-diff mode drops {len(PLAIN_DIFF_SECRETS)} secret files")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
