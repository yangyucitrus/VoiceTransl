from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .yaml_compat import safe_dump, safe_load


DEFAULT_SETTINGS: dict[str, Any] = {
    "asr": {"engine": "transwithai_whisper_ja", "device_preset": "gpu_quality"},
    "vad": {"preset": "standard_asmr"},
    "pipeline": {
        "reuse_cache": True,
        "continue_on_error": True,
        "transcribe_only": False,
        "preflight_translation_api": True,
    },
    "subtitle": {
        "merge": {
            "same_vad_max_gap_ms": 350,
            "cross_vad_max_gap_ms": 150,
            "max_segment_duration_ms": 6000,
            "min_segment_duration_ms": 500,
            "max_ja_chars": 42,
            "max_zh_chars": 32,
        },
        "format": {
            "zh_srt_max_line_chars": 18,
            "combine_srt_ja_max_line_chars": 24,
            "combine_srt_zh_max_line_chars": 18,
            "max_lines": 2,
        },
    },
    "translator": {
        "endpoint": "https://api.deepseek.com",
        "model": "deepseek-v4-flash",
        "profile": "ASMR_Adult_2D.md",
    },
    "models": {
        "transwithai_whisper_ja": "models/transwithai-whisper-ja-1.5b-ct2",
        "whisper_vad_onnx": "models/whisper-vad-asmr-onnx/model.onnx",
        "whisper_vad_metadata": "models/whisper-vad-asmr-onnx/model_metadata.json",
        "whisper_base": "models/whisper-base",
        "sherpa_ja": "models/sherpa-ja",
    },
    "dictionaries": {
        "transcription_corrections": "dictionaries/transcription_corrections.txt",
        "translation_glossary": "dictionaries/translation_glossary.txt",
        "post_translation_replacements": "dictionaries/post_translation_replacements.txt",
    },
    "quality": {"enabled": True},
}


@dataclass(frozen=True)
class AppConfig:
    root: Path
    settings_path: Path
    env_path: Path
    settings: dict[str, Any]
    api_key: str | None

    def path_from_root(self, raw_path: str) -> Path:
        path = Path(raw_path)
        return path if path.is_absolute() else self.root / path


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def write_default_settings(path: Path) -> None:
    path.write_text(
        safe_dump(DEFAULT_SETTINGS),
        encoding="utf-8",
    )


def write_default_env(path: Path) -> None:
    path.write_text("VOICETRANSL_API_KEY=\n", encoding="utf-8")


def load_env_key(path: Path) -> str | None:
    if not path.exists():
        return None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("VOICETRANSL_API_KEY="):
            value = line.split("=", 1)[1].strip()
            return value or None
    return None


def load_config(root: Path, settings_path: Path | None = None) -> tuple[AppConfig, list[str]]:
    root = root.resolve()
    settings_path = (settings_path or root / "settings.yaml").resolve()
    env_path = root / ".env"
    messages: list[str] = []

    if not settings_path.exists():
        write_default_settings(settings_path)
        messages.append(f"Created settings template: {settings_path}")

    if not env_path.exists():
        write_default_env(env_path)
        messages.append(f"Created env template: {env_path}")

    raw_settings = safe_load(settings_path.read_text(encoding="utf-8")) or {}
    settings = deep_merge(DEFAULT_SETTINGS, raw_settings)
    api_key = load_env_key(env_path)
    return AppConfig(root, settings_path, env_path, settings, api_key), messages


def require_config_ready(config: AppConfig, transcribe_only: bool) -> None:
    if not config.settings_path.exists():
        raise RuntimeError(f"Missing settings file: {config.settings_path}")
    if not transcribe_only and not config.api_key:
        raise RuntimeError(
            f"Missing VOICETRANSL_API_KEY in {config.env_path}. "
            "Use --transcribe-only to skip translation."
        )
