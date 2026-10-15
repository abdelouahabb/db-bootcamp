#!/usr/bin/env python3
"""
5-Day Meteorological Database, Lakehouse & Polyglot Telemetry Engineering Bootcamp
Zero-Dependency Local Web Portal & Built-In Coursebook Reader Launcher

Usage:
  macOS / Linux : python3 start_bootcamp.py
  Windows       : python start_bootcamp.py
"""

import argparse
import functools
import http.server
import os
import socket
import socketserver
import sys
import threading
import time
import webbrowser


class QuietBootcampHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """Serves files from the bootcamp root directory with UTF-8 headers and clean logging."""

    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".md": "text/markdown; charset=utf-8",
        ".sql": "text/plain; charset=utf-8",
        ".py": "text/plain; charset=utf-8",
        ".js": "text/plain; charset=utf-8",
        ".yml": "text/plain; charset=utf-8",
        ".yaml": "text/plain; charset=utf-8",
        ".sh": "text/plain; charset=utf-8",
        ".html": "text/html; charset=utf-8",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def log_message(self, fmt, *args):
        # Keep terminal output clean and readable
        sys.stdout.write(f"  [HTTP] {self.address_string()} - {fmt % args}\n")


def find_available_port(host: str, preferred_port: int = 8088, max_tries: int = 25) -> int:
    """Finds preferred_port if free, or increments until an available port is found."""
    for offset in range(max_tries):
        port = preferred_port + offset
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                sock.bind((host, port))
                return port
            except OSError:
                continue
    raise RuntimeError(f"Could not bind to any port in range {preferred_port}..{preferred_port + max_tries}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Launch the 5-Day Meteorological Data Engineering Bootcamp Web Portal & Reader."
    )
    parser.add_argument("--host", default="127.0.0.1", help="Bind address (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8088, help="Preferred HTTP port (default: 8088)")
    parser.add_argument(
        "--no-browser",
        action="store_true",
        help="Start the HTTP server without automatically opening a browser tab",
    )
    args = parser.parse_args()

    bootcamp_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(bootcamp_dir)

    port = find_available_port(args.host, args.port)
    portal_url = f"http://{args.host}:{port}/bootcamp_portal.html"

    banner = f"""
================================================================================
  5-DAY WEATHER FORECAST & TELEMETRY DATABASE ENGINEERING BOOTCAMP
  Interactive Command Center, Physics Simulators & Built-In Coursebook Reader
================================================================================
  Root Directory : {bootcamp_dir}
  Portal URL     : {portal_url}
  Setup Guide    : http://{args.host}:{port}/bootcamp_portal.html?doc=ATTENDEE_SETUP_GUIDE.md
--------------------------------------------------------------------------------
  Tip: Click ANY .md coursebook, reference card, .sql, .js, .py, or .yml file
       inside the portal to read it in the Built-In Dark-Mode Viewer!
  Press Ctrl+C to stop the server.
================================================================================
"""
    print(banner)

    handler = functools.partial(QuietBootcampHTTPRequestHandler, directory=bootcamp_dir)
    socketserver.ThreadingTCPServer.allow_reuse_address = True

    with socketserver.ThreadingTCPServer((args.host, port), handler) as httpd:
        if not args.no_browser:
            def _open():
                time.sleep(0.35)
                try:
                    webbrowser.open(portal_url)
                except Exception:
                    pass

            threading.Thread(target=_open, daemon=True).start()

        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n  [INFO] Shutting down Bootcamp Portal HTTP server. Goodbye!")


if __name__ == "__main__":
    main()
