from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from .config import AppConfig


MANIFEST_SCHEMA_VERSION = 1
MANIFEST_NAME = "manifest.json"


def build_stage_fingerprints(
    config: AppConfig,
    input_path: Path,
    *,
    transcribe_only: bool,
) -> dict[str, str]:
    settings = config.settings
    models = settings["models"]
    dictionaries = settings["dictionaries"]
    source = _path_signature(input_path)
    audio = _digest({"schema": "audio-v1", "source": source})
    vad = _digest(
        {
            "schema": "vad-v1",
            "audio": audio,
            "preset": settings["vad"]["preset"],
            "model": _path_signature(
                config.path_from_root(models["whisper_vad_onnx"])
            ),
            "metadata": _content_signature(
                config.path_from_root(models["whisper_vad_metadata"])
            ),
            "whisper_base": _path_signature(
                config.path_from_root(models["whisper_base"])
            ),
        }
    )
    asr = _digest(
        {
            "schema": "asr-v2",
            "vad": vad,
            "engine": settings["asr"]["engine"],
            "device_preset": settings["asr"]["device_preset"],
            "intensity": settings["asr"].get("intensity", "medium"),
            "model": _path_signature(
                config.path_from_root(models["transwithai_whisper_ja"])
            ),
            "transcription_dictionary": _content_signature(
                config.path_from_root(dictionaries["transcription_corrections"])
            ),
            "subtitle_merge": settings["subtitle"]["merge"],
        }
    )
    profile_path = (
        config.root
        / "translation_guidelines"
        / str(settings["translator"]["profile"])
    )
    translation = _digest(
        {
            "schema": "translation-v2",
            "asr": asr,
            "enabled": not transcribe_only,
            "endpoint": settings["translator"]["endpoint"],
            "model": settings["translator"]["model"],
            "profile": _content_signature(profile_path),
            "translation_glossary": _content_signature(
                config.path_from_root(dictionaries["translation_glossary"])
            ),
            "post_translation_replacements": _content_signature(
                config.path_from_root(
                    dictionaries["post_translation_replacements"]
                )
            ),
            "subtitle_format": settings["subtitle"]["format"],
        }
    )
    quality = _digest(
        {
            "schema": "quality-v1",
            "asr": asr,
            "translation": translation,
            "settings": settings.get("quality", {}),
        }
    )
    return {
        "audio": audio,
        "vad": vad,
        "asr": asr,
        "translation": translation,
        "quality": quality,
    }


def load_manifest(output_dir: Path) -> dict[str, Any]:
    path = output_dir / MANIFEST_NAME
    if not path.exists():
        return {
            "schema_version": MANIFEST_SCHEMA_VERSION,
            "stages": {},
        }
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {
            "schema_version": MANIFEST_SCHEMA_VERSION,
            "stages": {},
            "legacy_manifest": True,
        }
    if not isinstance(decoded, dict):
        return {
            "schema_version": MANIFEST_SCHEMA_VERSION,
            "stages": {},
            "legacy_manifest": True,
        }
    stages = decoded.get("stages")
    if not isinstance(stages, dict):
        decoded["stages"] = {}
    return decoded


def write_manifest(output_dir: Path, manifest: dict[str, Any]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest["schema_version"] = MANIFEST_SCHEMA_VERSION
    manifest["updated_at"] = datetime.now(timezone.utc).isoformat()
    path = output_dir / MANIFEST_NAME
    pending = output_dir / f".{MANIFEST_NAME}.tmp"
    pending.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    pending.replace(path)


def initialize_manifest(
    output_dir: Path,
    input_path: Path,
    config: AppConfig,
) -> dict[str, Any]:
    manifest = load_manifest(output_dir)
    manifest["source_path"] = str(input_path.resolve())
    manifest["configuration"] = {
        "asr_engine": str(config.settings["asr"]["engine"]),
        "device_preset": str(config.settings["asr"]["device_preset"]),
        "transcription_intensity": str(
            config.settings["asr"].get("intensity", "medium")
        ),
        "vad_preset": str(config.settings["vad"]["preset"]),
        "translation_endpoint": str(config.settings["translator"]["endpoint"]),
        "translation_model": str(config.settings["translator"]["model"]),
    }
    return manifest


def is_stage_cache_valid(
    manifest: dict[str, Any],
    stage: str,
    fingerprint: str,
    required_paths: Iterable[Path],
) -> bool:
    stages = manifest.get("stages")
    if not isinstance(stages, dict):
        return False
    stage_record = stages.get(stage)
    return (
        isinstance(stage_record, dict)
        and stage_record.get("fingerprint") == fingerprint
        and all(path.exists() for path in required_paths)
    )


def record_stage(
    output_dir: Path,
    manifest: dict[str, Any],
    stage: str,
    fingerprint: str,
) -> None:
    stages = manifest.setdefault("stages", {})
    stages[stage] = {
        "fingerprint": fingerprint,
        "completed_at": datetime.now(timezone.utc).isoformat(),
    }
    write_manifest(output_dir, manifest)


def invalidate_manifest_stages(output_dir: Path, stages: Iterable[str]) -> None:
    path = output_dir / MANIFEST_NAME
    if not path.exists():
        return
    manifest = load_manifest(output_dir)
    stage_records = manifest.setdefault("stages", {})
    for stage in stages:
        stage_records.pop(stage, None)
    write_manifest(output_dir, manifest)


def _digest(payload: Any) -> str:
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _content_signature(path: Path) -> dict[str, Any]:
    resolved = path.resolve()
    if not resolved.is_file():
        return {"path": str(resolved), "missing": True}
    digest = hashlib.sha256()
    with resolved.open("rb") as stream:
        for chunk in iter(lambda: stream.read(64 * 1024), b""):
            digest.update(chunk)
    stat = resolved.stat()
    return {
        "path": str(resolved),
        "size": stat.st_size,
        "sha256": digest.hexdigest(),
    }


def _path_signature(path: Path) -> dict[str, Any]:
    resolved = path.resolve()
    if not resolved.exists():
        return {"path": str(resolved), "missing": True}
    if resolved.is_file():
        stat = resolved.stat()
        return {
            "path": str(resolved),
            "size": stat.st_size,
            "modified_ns": stat.st_mtime_ns,
        }
    entries: list[dict[str, Any]] = []
    for item in sorted(resolved.rglob("*"), key=lambda entry: str(entry).casefold()):
        if not item.is_file() or item.is_symlink():
            continue
        stat = item.stat()
        entries.append(
            {
                "path": str(item.relative_to(resolved)),
                "size": stat.st_size,
                "modified_ns": stat.st_mtime_ns,
            }
        )
    return {"path": str(resolved), "files": entries}
