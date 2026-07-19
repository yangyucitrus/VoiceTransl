from __future__ import annotations

import json
from pathlib import Path
import sys
from threading import Lock
from typing import Any, Callable
import wave


VadProgressHandler = Callable[[float], None]
_runtime_lock = Lock()
_runtime: tuple[Any, Any, Any] | None = None


class _ProgressTrackingVadModel:
    def __init__(
        self,
        model: Any,
        np: Any,
        on_progress: VadProgressHandler,
    ) -> None:
        self._model = model
        self._np = np
        self._on_progress = on_progress

    def __getattr__(self, name: str) -> Any:
        return getattr(self._model, name)

    def reset_states(self) -> None:
        self._model.reset_states()

    def audio_forward(self, audio: Any, sr: int = 16000) -> Any:
        self._model.reset_states()
        chunk_samples = int(self._model.chunk_samples)
        total_chunks = max(1, (len(audio) + chunk_samples - 1) // chunk_samples)
        probabilities = []
        for chunk_index, offset in enumerate(range(0, len(audio), chunk_samples), 1):
            chunk = audio[offset : offset + chunk_samples]
            if len(chunk) < chunk_samples:
                chunk = self._np.pad(
                    chunk,
                    (0, chunk_samples - len(chunk)),
                    mode="constant",
                )
            probabilities.append(self._model(chunk, sr))
            self._on_progress(chunk_index / total_chunks)
        if probabilities:
            return self._np.concatenate(probabilities)
        return self._np.array([])


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


def prepare_vad_runtime() -> tuple[Any, Any, Any]:
    """Load native VAD dependencies on the worker's main thread."""
    global _runtime
    with _runtime_lock:
        if _runtime is not None:
            return _runtime
        try:
            import numpy as np

            runtime_vad = Path(__file__).resolve().parents[1] / "runtime" / "whisper-vad"
            if runtime_vad.exists() and str(runtime_vad) not in sys.path:
                sys.path.insert(0, str(runtime_vad))
            from onnx_inference import WhisperVADOnnxWrapper, get_speech_timestamps
        except Exception as exc:
            raise RuntimeError(
                "Whisper VAD runtime is not installed. Install requirements-asmr.txt and "
                "make TransWithAI whisper-vad onnx_inference.py importable."
            ) from exc
        _runtime = (np, WhisperVADOnnxWrapper, get_speech_timestamps)
        return _runtime


def _load_pcm_16k_mono(audio_path: Path, np: Any) -> Any:
    with wave.open(str(audio_path), "rb") as audio_file:
        channels = audio_file.getnchannels()
        sample_rate = audio_file.getframerate()
        sample_width = audio_file.getsampwidth()
        if (channels, sample_rate, sample_width) != (1, 16000, 2):
            raise RuntimeError(
                "VAD requires the pipeline's 16 kHz mono 16-bit PCM WAV cache; "
                f"got channels={channels}, sample_rate={sample_rate}, sample_width={sample_width}."
            )
        frames = audio_file.readframes(audio_file.getnframes())
    return np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0


def detect_speech(
    audio_path: Path,
    model_path: Path,
    metadata_path: Path,
    preset_name: str,
    whisper_base_path: Path | None = None,
    on_progress: VadProgressHandler | None = None,
) -> dict[str, Any]:
    if not model_path.exists():
        raise RuntimeError(f"VAD model missing: {model_path}")
    if preset_name not in VAD_PRESETS:
        raise RuntimeError(f"Unknown VAD preset: {preset_name}")
    np, WhisperVADOnnxWrapper, get_speech_timestamps = prepare_vad_runtime()
    audio = _load_pcm_16k_mono(audio_path, np)
    runtime_metadata_path = metadata_path
    if whisper_base_path is not None and whisper_base_path.exists():
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        metadata["whisper_model_name"] = str(whisper_base_path)
        runtime_metadata_path = metadata_path.with_name("whisper_vad_runtime_metadata.json")
        runtime_metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    model = WhisperVADOnnxWrapper(str(model_path), metadata_path=str(runtime_metadata_path))
    preset = VAD_PRESETS[preset_name]

    timestamp_model = (
        _ProgressTrackingVadModel(model, np, on_progress)
        if on_progress is not None
        else model
    )
    segments = get_speech_timestamps(
        audio=audio,
        model=timestamp_model,
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
