from __future__ import annotations

import argparse
import sys
from pathlib import Path

from asmr.config import load_config
from asmr.models import check_model_readiness
from asmr.pipeline import process_files, run_smoke_test


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser("Japanese ASMR subtitle pipeline")
    parser.add_argument("inputs", nargs="*", help="Local audio/video files")
    parser.add_argument("--settings", help="Path to settings.yaml")
    parser.add_argument("--transcribe-only", action="store_true", help="Skip online translation")
    parser.add_argument("--no-cache", action="store_true", help="Ignore reusable cache")
    parser.add_argument("--skip-api-preflight", action="store_true", help="Skip lightweight API model-list/auth preflight")
    parser.add_argument("--limit-segments", type=int, help="Only transcribe the first N VAD segments (debug)")
    parser.add_argument("--start-segment", type=int, default=0, help="Start from VAD segment N (1-based, debug)")
    parser.add_argument("--smoke-test", action="store_true", help="Run deterministic JSON/SRT/quality smoke test")
    parser.add_argument("--check-models", action="store_true", help="Check configured model paths and exit")
    return parser


def main(argv: list[str] | None = None) -> int:
    if sys.platform == "win32":
        try:
            sys.stdout.reconfigure(encoding="utf-8")
            sys.stderr.reconfigure(encoding="utf-8")
        except Exception:
            pass
    args = build_parser().parse_args(argv)
    root = Path(__file__).resolve().parent
    config, messages = load_config(root, Path(args.settings) if args.settings else None)
    for message in messages:
        print(f"[config] {message}")

    if args.smoke_test:
        out_dir = run_smoke_test(root)
        print(f"[smoke] wrote {out_dir}")
        return 0

    if args.check_models:
        missing = check_model_readiness(config, transcribe_only=args.transcribe_only)
        if missing:
            for item in missing:
                print(f"[missing] {item}")
            return 1
        print("[ok] all required model paths exist")
        return 0

    if not args.inputs:
        print("No input files provided. Use --smoke-test for a deterministic local test.", file=sys.stderr)
        return 2

    inputs = [Path(item) for item in args.inputs]
    try:
        results = process_files(
            config,
            inputs,
            transcribe_only=args.transcribe_only or bool(config.settings["pipeline"].get("transcribe_only")),
            no_cache=args.no_cache,
            skip_api_preflight=args.skip_api_preflight,
            limit_segments=args.limit_segments,
            start_segment=args.start_segment,
        )
    except Exception as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 1

    failed = False
    for result in results:
        suffix = f", warnings={result.warnings}" if result.warnings else ""
        if result.error:
            suffix += f", error={result.error}"
        print(f"[{result.status}] {result.input_path} -> {result.output_dir}{suffix}")
        if result.status == "failed":
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
