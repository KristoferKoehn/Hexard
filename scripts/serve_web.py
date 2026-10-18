#!/usr/bin/env python3
"""Serve the web build with the headers a Godot page needs.

`python -m http.server` is not enough for two independent reasons:

1. It sends no Cross-Origin-* headers. A page that is embedded in an iframe (or hosted on a
   site that sets COEP) refuses to load subresources that lack them, which surfaces in Chrome
   as "each embedded iframe must also specify this policy" plus a block of failed requests.
2. It serves `.wasm` as `application/octet-stream`, which defeats streaming instantiation.

Usage:
    python tools/serve_web.py [port]        # then open http://127.0.0.1:<port>/

The headers are the single-threaded pair: this build has `thread_support=false`, so
SharedArrayBuffer is not used, but COEP/CORP are still set because they are harmless here and
required wherever the game is framed.
"""

import functools
import http.server
import pathlib
import socketserver
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "build" / "web"
DEFAULT_PORT = 8080

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".json": "application/json",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".css": "text/css; charset=utf-8",
    ".worklet.js": "text/javascript; charset=utf-8",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, **MIME}

    def end_headers(self) -> None:
        # Required when the hosting page is cross-origin isolated, and harmless otherwise.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        # A fresh build should never be served from cache while iterating.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("  %s\n" % (fmt % args))


def main() -> int:
    if not (ROOT / "index.html").exists():
        print("no build at %s - run the web export first" % ROOT)
        return 1
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    handler = functools.partial(Handler, directory=str(ROOT))
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", port), handler) as server:
        print("serving %s at http://127.0.0.1:%d/" % (ROOT, port))
        print("COOP/COEP/CORP headers set; .wasm served as application/wasm")
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
