from __future__ import annotations

import json
from pathlib import Path
from typing import Any
import sys


VAD_PRESETS: dict[str, dict[str, Any]] = {
    "standard_asmr": {
        "threshold": 0.5,
        "min_speech_duration_ms": 300,
        "min_silence_duration_ms": 100,
        "speech_pad_ms": 200,
        "max_speech_duration_s": 30,
    },
    "whisper_sensitive": {
        "threshold": 0.4,
        "min_speech_duration_ms": 200,
        "min_silence_duration_ms": 80,
        "speech_pad_ms": 250,
        "max_speech_duration_s": 30,
    },
    "clean_conservative": {
        "threshold": 0.6,
        "min_speech_duration_ms": 400,
        "min_silence_duration_ms": 180,
        "speech_pad_ms": 150,
        "max_speech_duration_s": 30,
    },
}


def detect_speech(audio_path: Path, model_path: Path, metadata_path: Path, preset_name: str, whisper_base_path: Path | None = None) -> dict[str, Any]:
    if not model_path.exists():
        raise RuntimeError(f"VAD model missing: {model_path}")
    if preset_name not in VAD_PRESETS:
        raise RuntimeError(f"Unknown VAD preset: {preset_name}")
    try:
        import librosa
        runtime_vad = Path(__file__).resolve().parents[1] / "runtime" / "whisper-vad"
        if runtime_vad.exists() and str(runtime_vad) not in sys.path:
            sys.path.insert(0, str(runtime_vad))
        from onnx_inference import WhisperVADOnnxWrapper, get_speech_timestamps
    except Exception as exc:
        raise RuntimeError(
            "Whisper VAD runtime is not installed. Install requirements-asmr.txt and "
            "make TransWithAI whisper-vad onnx_inference.py importable."
        ) from exc

    audio, _ = librosa.load(str(audio_path), sr=16000)
    runtime_metadata_path = metadata_path
    if whisper_base_path is not None and whisper_base_path.exists():
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        metadata["whisper_model_name"] = str(whisper_base_path)
        runtime_metadata_path = metadata_path.with_name("whisper_vad_runtime_metadata.json")
        runtime_metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    model = WhisperVADOnnxWrapper(str(model_path), metadata_path=str(runtime_metadata_path))
    preset = VAD_PRESETS[preset_name]
    segments = get_speech_timestamps(
        audio=audio,
        model=model,
        sampling_rate=16000,
        return_seconds=True,
        **preset,
    )
    normalized = []
    for idx, seg in enumerate(segments, 1):
        start = float(seg["start"])
        end = float(seg["end"])
        item = {"id": idx, "start": start, "end": end, "duration": end - start}
        for key in ("avg_prob", "min_prob", "max_prob"):
            if key in seg:
                item[key] = float(seg[key])
        normalized.append(item)
    return {"schema_version": 1, "preset": preset_name, "segments": normalized}
