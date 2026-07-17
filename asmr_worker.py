"""JSONL worker entrypoint for native desktop frontends."""

from __future__ import annotations

from asmr.worker_protocol import serve_stdio


if __name__ == "__main__":
    raise SystemExit(serve_stdio())
