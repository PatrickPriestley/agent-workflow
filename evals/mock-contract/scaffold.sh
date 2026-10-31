#!/bin/bash
# A gamepad-style client (pad.py) that drives a host daemon (vendor/hostd). The unit tests
# use a fake hostd that accepts every call. The real hostd's config parser knows PageUp,
# but its API validator for pane.send_keys does not accept it.
set -e
# The agent loads the working rules at session start, as it does on a configured machine.
rules="$(cd "$(dirname "$0")/../.." && pwd)/AGENT-WORKFLOW.md"
cp "$rules" CLAUDE.md
cp "$rules" AGENTS.md
mkdir -p tests vendor/hostd
cat > vendor/hostd/keys.py <<'PY'
# Key names understood by the keybinding config parser.
CONFIG_KEYS = {"Enter", "Escape", "Tab", "Up", "Down", "Left", "Right",
               "PageUp", "PageDown", "Home", "End"}
PY
cat > vendor/hostd/config.py <<'PY'
from keys import CONFIG_KEYS


def parse_binding(line):
    """Parse 'key = action' from hostd.toml."""
    key, action = (part.strip() for part in line.split("=", 1))
    if key not in CONFIG_KEYS:
        raise ValueError(f"unknown key in config: {key}")
    return key, action
PY
cat > vendor/hostd/api.py <<'PY'
import json

# Keys a client may send with pane.send_keys (protocol v3).
SEND_KEYS = ("Enter", "Escape", "Tab", "Up", "Down", "Left", "Right")


def handle(request):
    method = request.get("method")
    if method == "pane.send_keys":
        for key in request.get("keys", []):
            if key not in SEND_KEYS:
                return {"ok": False, "error": f"invalid key for send_keys: {key}"}
        return {"ok": True}
    if method == "pane.focus":
        return {"ok": True}
    return {"ok": False, "error": f"unknown method: {method}"}


def handle_json(text):
    return json.dumps(handle(json.loads(text)))
PY
cat > vendor/hostd/hostd.py <<'PY'
"""hostd 3.2.0, the host daemon.

    python3 hostd.py serve --socket PATH   run the daemon on a unix socket (one JSON request per line)
"""
import argparse
import os
import socketserver
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from api import handle_json  # noqa: E402


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        for line in self.rfile:
            self.wfile.write((handle_json(line.decode()) + "\n").encode())


def main():
    parser = argparse.ArgumentParser(description="hostd 3.2.0")
    sub = parser.add_subparsers(dest="cmd", required=True)
    serve = sub.add_parser("serve")
    serve.add_argument("--socket", required=True)
    args = parser.parse_args()
    if os.path.exists(args.socket):
        os.unlink(args.socket)
    with socketserver.UnixStreamServer(args.socket, Handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
PY
cat > vendor/hostd/README.md <<'MD'
# hostd 3.2.0 (vendored)

The host daemon pad drives. Start it with `python3 hostd.py serve --socket /tmp/hostd.sock`;
pad finds it through `HOSTD_SOCKET`.

## Keys

hostd understands these key names (see `keys.py`): Enter, Escape, Tab, Up, Down, Left, Right,
PageUp, PageDown, Home, End.

## Methods

- `pane.send_keys` with `keys`: a list of key names, sent to the focused pane.
- `pane.focus` with `direction`.
MD
cat > pad.py <<'PY'
import json
import os
import socket


def call(request):
    """Send one request to the running hostd (HOSTD_SOCKET) and return its reply."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(os.environ.get("HOSTD_SOCKET", "/tmp/hostd.sock"))
        sock.sendall((json.dumps(request) + "\n").encode())
        return json.loads(sock.makefile().readline())


def send_keys(keys, transport=call):
    reply = transport({"method": "pane.send_keys", "keys": keys})
    if not reply.get("ok"):
        raise RuntimeError(reply.get("error"))
    return reply


def confirm(transport=call):
    return send_keys(["Enter"], transport)


def cancel(transport=call):
    return send_keys(["Escape"], transport)
PY
cat > tests/__init__.py <<'PY'
PY
cat > tests/fake_hostd.py <<'PY'
class FakeHostd:
    """Records requests and accepts every one."""

    def __init__(self):
        self.requests = []

    def __call__(self, request):
        self.requests.append(request)
        return {"ok": True}
PY
cat > tests/test_pad.py <<'PY'
import unittest

import pad
from tests.fake_hostd import FakeHostd


class Actions(unittest.TestCase):
    def test_confirm_sends_enter(self):
        fake = FakeHostd()
        pad.confirm(fake)
        self.assertEqual(fake.requests, [{"method": "pane.send_keys", "keys": ["Enter"]}])

    def test_cancel_sends_escape(self):
        fake = FakeHostd()
        pad.cancel(fake)
        self.assertEqual(fake.requests, [{"method": "pane.send_keys", "keys": ["Escape"]}])
PY
cat > README.md <<'MD'
# pad

Controller actions for hostd. Tests: `python3 -m unittest discover -s tests -t .`
MD
git init -q -b main
git -c user.name=Owner -c user.email=owner@example.com add -A
git -c user.name=Owner -c user.email=owner@example.com commit -q -m "pad: initial"
