"""Tiny mock of the Throne API for testing throne-gate.sh offline.

POST /api/scan         -> 401 unless Authorization is "Bearer good", else a
                          scan_id chosen from the target (so GET can echo the
                          right fixture).
GET  /api/scans/<id>   -> the matching fixture, already "complete".

It also mocks just enough of the GitHub REST API for the sticky PR comment
(list/create/update issue comments), so the comment path is testable offline:

GET   /repos/<o>/<r>/issues/<pr>/comments   -> paginated comment list
POST  /repos/<o>/<r>/issues/<pr>/comments   -> create (403 for token "denied")
PATCH /repos/<o>/<r>/issues/comments/<id>   -> update (403 for token "denied")

Plus two white-box control endpoints for the test harness:

GET  /__control/comments?repo=<o>/<r>&pr=<n> -> every stored comment, unpaged
POST /__control/seed                         -> bulk-add filler comments
                                                {"repo":.., "pr":.., "count":..}
"""

import json
import re
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

FIXTURES = {
    "fit-npm": {
        "status": "complete",
        "progress": None,
        "verdict": {"value": "fit", "reason": None, "summary": "0 fail / 1 warn across 2 clients"},
        "security": {"verdict": "review", "findings": [
            {"severity": "MEDIUM", "id": "unpinned-dependency", "title": "Dependency installed from a floating version range", "file": "package.json", "line": 12},
        ]},
        "target": {"type": "npm", "normalized": "@scope/cool-mcp"},
        "clients": [
            {"name": "claude code", "steps": [{"status": "pass"}, {"status": "pass"}]},
            {"name": "cursor", "steps": [{"status": "pass"}, {"status": "warn"}]},
        ],
    },
    "not-fit": {
        "status": "complete",
        "verdict": {"value": "not_fit", "reason": None, "summary": "12 fail / 0 warn across 2 clients"},
        "security": {"verdict": "review", "findings": [{"severity": "HIGH"}, {"severity": "LOW"}]},
        "target": {"type": "npm", "normalized": "broken-mcp"},
        "clients": [{"name": "claude code", "steps": [{"status": "fail"}]}],
    },
    "inc-creds-gh": {
        "status": "complete",
        "verdict": {"value": "inconclusive", "reason": "needs_credentials", "summary": "needs credentials: exits asking for an API key"},
        "security": {"verdict": "clean", "findings": []},
        "target": {"type": "github", "normalized": "https://github.com/Owner/Repo-Name.git"},
        "clients": [{"name": "claude code", "steps": [{"status": "skipped"}]}],
    },
    "fit-pypi": {
        "status": "complete",
        "verdict": {"value": "fit", "reason": None, "summary": "0 fail / 0 warn across 2 clients"},
        "security": {"verdict": "clean", "findings": []},
        "target": {"type": "pypi", "normalized": "some-pypi-mcp"},
        "clients": [{"name": "claude code", "steps": [{"status": "pass"}]}],
    },
    # Compatible, but the source scan flagged findings including a high-severity
    # one. Mixed severities (and a lower-case spelling) exercise the breakdown
    # and the case-insensitive high-severity gate.
    "fit-high-sec": {
        "status": "complete",
        "verdict": {"value": "fit", "reason": None, "summary": "0 fail / 0 warn across 2 clients"},
        "security": {"verdict": "review", "findings": [
            {"severity": "HIGH", "id": "shell-exec", "title": "Spawns a shell with unsanitised input", "file": "src/tools/run.ts", "line": 88},
            {"severity": "medium", "title": "Reads process environment on startup"},
            {"severity": "LOW", "id": "verbose-logging"},
        ]},
        "target": {"type": "npm", "normalized": "sketchy-mcp"},
        "clients": [{"name": "claude code", "steps": [{"status": "pass"}]}],
    },
    "failed-scan": {
        "status": "failed",
        "error": "sandbox exploded",
        "target": {"type": "npm", "normalized": "flaky-mcp"},
    },
    "unknown-verdict": {
        "status": "complete",
        "verdict": {"value": "unknown", "reason": None, "summary": ""},
        "security": {"verdict": "not_run", "findings": []},
        "target": {"type": "npm", "normalized": "weird-mcp"},
        "clients": [],
    },
}

# target string -> fixture key
TARGET_MAP = {
    "@scope/cool-mcp": "fit-npm",
    "broken-mcp": "not-fit",
    "https://github.com/Owner/Repo-Name": "inc-creds-gh",
    "uvx some-pypi-mcp": "fit-pypi",
    "sketchy-mcp": "fit-high-sec",
    "flaky-mcp": "failed-scan",
    "weird-mcp": "unknown-verdict",
    # Accepted on POST, then every GET 404s — the scan vanished server-side.
    "vanished-mcp": "vanished",
    # First two GETs return a 500, then the fit-pypi fixture: the poll loop
    # must ride out transient server errors without corrupting its state.
    "wobbly-mcp": "wobbly",
}

_LAST = {}
_WOBBLES = {"left": 2}

# GitHub-comment mock state: "<owner>/<repo>#<pr>" -> list of comment dicts.
_COMMENTS = {}
_NEXT_ID = {"n": 1000}

_GH_LIST_RE = re.compile(r"^/repos/([^/]+/[^/]+)/issues/(\d+)/comments$")
_GH_EDIT_RE = re.compile(r"^/repos/([^/]+/[^/]+)/issues/comments/(\d+)$")


def _pr_key(repo, pr):
    return f"{repo}#{pr}"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length) or b"{}")

    # The gate sends "Bearer <github-token>"; "denied" simulates a workflow
    # token without pull-requests: write, which GitHub answers with a 403.
    def _gh_denied(self):
        return self.headers.get("Authorization") == "Bearer denied"

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/__control/seed":
            body = self._read_json()
            key = _pr_key(body["repo"], body["pr"])
            comments = _COMMENTS.setdefault(key, [])
            for i in range(body["count"]):
                comments.append({"id": _NEXT_ID["n"], "body": f"filler {i}"})
                _NEXT_ID["n"] += 1
            return self._send(200, {"ok": True})
        m = _GH_LIST_RE.match(path)
        if m:
            if self._gh_denied():
                return self._send(403, {"message": "Resource not accessible by integration"})
            comment = {"id": _NEXT_ID["n"], "body": self._read_json().get("body", "")}
            _NEXT_ID["n"] += 1
            _COMMENTS.setdefault(_pr_key(m.group(1), int(m.group(2))), []).append(comment)
            return self._send(201, comment)
        if path != "/api/scan":
            return self._send(404, {"error": "nope"})
        if self.headers.get("Authorization") != "Bearer good":
            return self._send(401, {"error": "invalid API key"})
        target = self._read_json().get("target", "")
        key = TARGET_MAP.get(target)
        if not key:
            return self._send(400, {"error": f"unknown target {target}"})
        scan_id = f"scan-{key}"
        _LAST[scan_id] = key
        self._send(200, {"scan_id": scan_id, "status": "queued"})

    def do_PATCH(self):
        m = _GH_EDIT_RE.match(urlparse(self.path).path)
        if not m:
            return self._send(404, {"error": "nope"})
        if self._gh_denied():
            return self._send(403, {"message": "Resource not accessible by integration"})
        cid = int(m.group(2))
        for comments in _COMMENTS.values():
            for c in comments:
                if c["id"] == cid:
                    c["body"] = self._read_json().get("body", "")
                    return self._send(200, c)
        self._send(404, {"message": "Not Found"})

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/__control/comments":
            q = parse_qs(parsed.query)
            key = _pr_key(q["repo"][0], int(q["pr"][0]))
            return self._send(200, _COMMENTS.get(key, []))
        m = _GH_LIST_RE.match(path)
        if m:
            q = parse_qs(parsed.query)
            page = int(q.get("page", ["1"])[0])
            per = int(q.get("per_page", ["30"])[0])
            comments = _COMMENTS.get(_pr_key(m.group(1), int(m.group(2))), [])
            return self._send(200, comments[(page - 1) * per : page * per])
        if path.startswith("/api/scans/"):
            scan_id = path.rsplit("/", 1)[-1]
            key = _LAST.get(scan_id)
            if not key or key == "vanished":
                return self._send(404, {"error": "scan not found"})
            if key == "wobbly":
                if _WOBBLES["left"] > 0:
                    _WOBBLES["left"] -= 1
                    return self._send(500, {"error": "hiccup"})
                key = "fit-pypi"
            return self._send(200, FIXTURES[key])
        self._send(404, {"error": "nope"})


if __name__ == "__main__":
    import sys

    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8799
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
