#!/usr/bin/env python3
"""Static file server with HTTP Range support for the launcher e2e tests
(python's http.server ignores Range). Logs one line per request to stderr:
  GET <path> range=<header or ->
Usage: range_server.py <port> <dir>"""
import http.server
import os
import re
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        rng = self.headers.get("Range")
        sys.stderr.write("GET %s range=%s\n" % (self.path, rng or "-"))
        sys.stderr.flush()
        if self.path.startswith("/r/"):  # redirect test: /r/<x> -> /<x>
            self.send_response(302)
            self.send_header("Location", "http://%s%s" % (self.headers.get("Host"), self.path[2:]))
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            self.send_error(404)
            return
        size = os.path.getsize(path)
        start, end, code = 0, size - 1, 200
        m = re.match(r"bytes=(\d+)-(\d*)$", rng or "")
        if m:
            start = int(m.group(1))
            if m.group(2):
                end = min(int(m.group(2)), size - 1)
            if start >= size:
                self.send_response(416)
                self.send_header("Content-Range", "bytes */%d" % size)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            code = 206
        self.send_response(code)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(end - start + 1))
        if code == 206:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(start)
            left = end - start + 1
            while left > 0:
                chunk = f.read(min(65536, left))
                if not chunk:
                    break
                self.wfile.write(chunk)
                left -= len(chunk)


if __name__ == "__main__":
    os.chdir(sys.argv[2])
    http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
