"""Tiny mock of the Throne API for testing throne-gate.sh offline.

POST /api/scan         -> 401 unless Authorization is "Bearer good", else a
                          scan_id chosen from the target (so GET can echo the
                          right fixture).
GET  /api/scans/<id>   -> the matching fixture, already "complete".
"""

import json
from http.server import BaseHTTPRequestHandler, HTTPServer

FIXTURES = {
    "fit-npm": {
        "status": "complete",
        "progress": None,
        "verdict": {"value": "fit", "reason": None, "summary": "0 fail / 1 warn across 2 clients"},
        "security": {"verdict": "review", "findings": [{"severity": "MEDIUM"}]},
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
}

# target string -> fixture key
TARGET_MAP = {
    "@scope/cool-mcp": "fit-npm",
    "broken-mcp": "not-fit",
    "https://github.com/Owner/Repo-Name": "inc-creds-gh",
}

_LAST = {}


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

    def do_POST(self):
        if self.path != "/api/scan":
            return self._send(404, {"error": "nope"})
        if self.headers.get("Authorization") != "Bearer good":
            return self._send(401, {"error": "invalid API key"})
        length = int(self.headers.get("Content-Length", 0))
        target = json.loads(self.rfile.read(length) or b"{}").get("target", "")
        key = TARGET_MAP.get(target)
        if not key:
            return self._send(400, {"error": f"unknown target {target}"})
        scan_id = f"scan-{key}"
        _LAST[scan_id] = key
        self._send(200, {"scan_id": scan_id, "status": "queued"})

    def do_GET(self):
        if self.path.startswith("/api/scans/"):
            scan_id = self.path.rsplit("/", 1)[-1]
            key = _LAST.get(scan_id)
            if not key:
                return self._send(404, {"error": "scan not found"})
            return self._send(200, FIXTURES[key])
        self._send(404, {"error": "nope"})


if __name__ == "__main__":
    import sys

    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8799
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
