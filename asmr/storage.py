from __future__ import annotations

import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from .cache_manifest import MANIFEST_NAME, invalidate_manifest_stages
from .pipeline import output_paths


CLEANUP_MODES = frozenset({"safe_cache", "all_cache", "delete_result"})
RETRY_STAGES = frozenset({"translation", "transcription"})
SAFE_CACHE_NAMES = (
    "audio.16k.wav",
    "asr_chunks",
    "asr_partial.jsonl",
    "galtransl_project",
)


@dataclass(frozen=True)
class OutputReference:
    input_path: Path
    output_dir: Path


def normalize_output_references(raw_items: Any) -> list[OutputReference]:
    if not isinstance(raw_items, list) or not raw_items:
        raise ValueError("items must be a non-empty list")
    references: list[OutputReference] = []
    seen: set[str] = set()
    for raw_item in raw_items:
        if not isinstance(raw_item, dict):
            raise TypeError("Every output item must be an object")
        raw_input = raw_item.get("input_path")
        raw_output = raw_item.get("output_dir")
        if not isinstance(raw_input, str) or not raw_input.strip():
            raise ValueError("Every output item requires input_path")
        if not isinstance(raw_output, str) or not raw_output.strip():
            raise ValueError("Every output item requires output_dir")
        input_path = Path(raw_input).expanduser().resolve()
        output_dir = Path(raw_output).expanduser().resolve()
        expected, _cache_dir, _stem = output_paths(input_path)
        if _path_key(expected.resolve()) != _path_key(output_dir):
            raise ValueError(
                f"Output directory does not match its source file: {output_dir}"
            )
        if not output_dir.name.casefold().endswith(".voicetransl"):
            raise ValueError(f"Refusing to manage a non-VoiceTransl directory: {output_dir}")
        if output_dir.is_symlink():
            raise ValueError(f"Refusing to manage a symbolic link: {output_dir}")
        if output_dir.exists() and not output_dir.is_dir():
            raise ValueError(f"Refusing to manage a non-directory output: {output_dir}")
        key = _path_key(output_dir)
        if key not in seen:
            seen.add(key)
            references.append(OutputReference(input_path, output_dir))
    return references


def inspect_outputs(references: Iterable[OutputReference]) -> dict[str, Any]:
    items = [_inspect_output(reference) for reference in references]
    return {
        "items": items,
        "summary": {
            "result_count": len(items),
            "final_bytes": sum(item["final_bytes"] for item in items),
            "cache_bytes": sum(item["cache_bytes"] for item in items),
            "reclaimable_bytes": sum(
                item["reclaimable_bytes"] for item in items
            ),
        },
    }


def cleanup_outputs(
    references: Iterable[OutputReference],
    mode: str,
) -> dict[str, Any]:
    if mode not in CLEANUP_MODES:
        raise ValueError(
            f"mode must be one of: {', '.join(sorted(CLEANUP_MODES))}"
        )
    results: list[dict[str, Any]] = []
    for reference in references:
        before = _inspect_output(reference)
        if reference.output_dir.exists():
            if mode == "safe_cache":
                _safe_cleanup(reference.output_dir)
            elif mode == "all_cache":
                _remove_path(reference.output_dir / "cache")
            else:
                shutil.rmtree(reference.output_dir)
        after = _inspect_output(reference)
        results.append(
            {
                **after,
                "freed_bytes": max(
                    0,
                    before["final_bytes"]
                    + before["cache_bytes"]
                    - after["final_bytes"]
                    - after["cache_bytes"],
                ),
                "deleted": mode == "delete_result"
                and not reference.output_dir.exists(),
            }
        )
    return {
        "mode": mode,
        "items": results,
        "freed_bytes": sum(item["freed_bytes"] for item in results),
        "deleted_count": sum(1 for item in results if item["deleted"]),
    }


def prepare_retry(
    reference: OutputReference,
    stage: str,
) -> dict[str, Any]:
    if stage not in RETRY_STAGES:
        raise ValueError(
            f"stage must be one of: {', '.join(sorted(RETRY_STAGES))}"
        )
    output_dir = reference.output_dir
    cache_dir = output_dir / "cache"
    stem = reference.input_path.stem
    before = _inspect_output(reference)
    if stage == "translation":
        targets = (
            cache_dir / f"{stem}.zh.json",
            cache_dir / "galtransl_project",
            cache_dir / "quality_report.json",
            output_dir / f"{stem}.zh.srt",
            output_dir / f"{stem}.combine.srt",
        )
        invalidated = ("translation", "quality")
    else:
        targets = (
            cache_dir / f"{stem}.ja.json",
            cache_dir / f"{stem}.zh.json",
            cache_dir / "asr_chunks",
            cache_dir / "asr_partial.jsonl",
            cache_dir / "galtransl_project",
            cache_dir / "quality_report.json",
            output_dir / f"{stem}.ja.srt",
            output_dir / f"{stem}.zh.srt",
            output_dir / f"{stem}.combine.srt",
        )
        invalidated = ("asr", "translation", "quality")
    for target in targets:
        _remove_path(target)
    invalidate_manifest_stages(output_dir, invalidated)
    after = _inspect_output(reference)
    return {
        "stage": stage,
        **after,
        "freed_bytes": max(
            0,
            before["final_bytes"]
            + before["cache_bytes"]
            - after["final_bytes"]
            - after["cache_bytes"],
        ),
    }


def _inspect_output(reference: OutputReference) -> dict[str, Any]:
    output_dir = reference.output_dir
    if not output_dir.exists():
        return {
            "input_path": str(reference.input_path),
            "output_dir": str(output_dir),
            "exists": False,
            "final_bytes": 0,
            "cache_bytes": 0,
            "reclaimable_bytes": 0,
            "cache_state": "none",
        }
    cache_dir = output_dir / "cache"
    if cache_dir.is_symlink():
        raise ValueError(f"Refusing to inspect a symbolic cache directory: {cache_dir}")
    cache_bytes = _path_size(cache_dir)
    total_bytes = _path_size(output_dir)
    reclaimable_bytes = sum(
        _path_size(cache_dir / name) for name in SAFE_CACHE_NAMES
    )
    manifest_exists = (output_dir / MANIFEST_NAME).is_file()
    cache_state = (
        "none"
        if cache_bytes == 0
        else "tracked"
        if manifest_exists
        else "legacy"
    )
    return {
        "input_path": str(reference.input_path),
        "output_dir": str(output_dir),
        "exists": True,
        "final_bytes": max(0, total_bytes - cache_bytes),
        "cache_bytes": cache_bytes,
        "reclaimable_bytes": reclaimable_bytes,
        "cache_state": cache_state,
    }


def _safe_cleanup(output_dir: Path) -> None:
    cache_dir = output_dir / "cache"
    if cache_dir.is_symlink():
        raise ValueError(f"Refusing to clean a symbolic cache directory: {cache_dir}")
    for name in SAFE_CACHE_NAMES:
        _remove_path(cache_dir / name)


def _remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
    elif path.is_dir():
        shutil.rmtree(path)


def _path_size(path: Path) -> int:
    if path.is_symlink() or not path.exists():
        return 0
    if path.is_file():
        return path.stat().st_size
    total = 0
    for root, directories, files in os.walk(path, followlinks=False):
        root_path = Path(root)
        directories[:] = [
            name for name in directories if not (root_path / name).is_symlink()
        ]
        for name in files:
            file_path = root_path / name
            if not file_path.is_symlink():
                total += file_path.stat().st_size
    return total


def _path_key(path: Path) -> str:
    return os.path.normcase(str(path.resolve()))
