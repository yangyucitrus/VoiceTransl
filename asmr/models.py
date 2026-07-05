from __future__ import annotations

from pathlib import Path

from .config import AppConfig


def check_model_readiness(config: AppConfig, transcribe_only: bool) -> list[str]:
    settings = config.settings
    model_paths = settings["models"]
    required = [
        ("ASR model", model_paths["transwithai_whisper_ja"]),
        ("Whisper VAD ONNX", model_paths["whisper_vad_onnx"]),
        ("Whisper VAD metadata", model_paths["whisper_vad_metadata"]),
        ("Whisper base assets", model_paths["whisper_base"]),
    ]
    missing: list[str] = []
    for label, raw_path in required:
        path = config.path_from_root(raw_path)
        if not path.exists():
            missing.append(f"{label} missing: {path}")

    if settings["asr"].get("engine") == "sherpa_ja":
        sherpa_path = config.path_from_root(model_paths["sherpa_ja"])
        if not sherpa_path.exists():
            missing.append(f"sherpa-onnx Japanese model missing: {sherpa_path}")

    return missing


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
