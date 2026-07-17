from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any, Callable

from .audio import find_ffmpeg


def extract_region(root: Path, audio_path: Path, start: float, end: float, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            find_ffmpeg(root),
            "-y",
            "-ss",
            f"{start:.3f}",
            "-to",
            f"{end:.3f}",
            "-i",
            str(audio_path),
            "-ac",
            "1",
            "-ar",
            "16000",
            str(output_path),
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def transcribe_regions(
    root: Path,
    audio_path: Path,
    vad_doc: dict[str, Any],
    model_path: Path,
    device_preset: str,
    work_dir: Path,
    partial_path: Path | None = None,
    limit_segments: int | None = None,
    start_segment: int = 0,
    check_cancel: Callable[[], None] | None = None,
    on_progress: Callable[[int, int], None] | None = None,
) -> list[dict[str, Any]]:
    if not model_path.exists():
        raise RuntimeError(f"ASR model missing: {model_path}")
    vad_segments = vad_doc.get("segments") or []
    if not vad_segments:
        return []

    # Debug range: --start-segment is 1-based, --limit-segments counts from
    # the (already offset) slice.
    if start_segment > 0:
        vad_segments = vad_segments[start_segment - 1:]
    if limit_segments is not None and limit_segments > 0:
        vad_segments = vad_segments[:limit_segments]
    if not vad_segments:
        return []

    # Resume from checkpoint. Partial file is JSONL: one ASR segment per line.
    # An interrupted write at most corrupts the final line, which we skip.
    results: list[dict[str, Any]] = []
    done_vad_ids: set[int] = set()
    if partial_path is not None and partial_path.exists():
        for line in partial_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                seg = json.loads(line)
            except json.JSONDecodeError:
                continue
            results.append(seg)
            vad_id = seg.get("vad", {}).get("segment_id")
            if vad_id is not None:
                done_vad_ids.add(vad_id)
        if results:
            print(f"[asr] resumed {len(results)} segments from checkpoint")

    _ensure_cuda_dlls()
    try:
        from faster_whisper import WhisperModel
    except Exception as exc:
        raise RuntimeError("faster-whisper is not installed. Install requirements-asmr.txt.") from exc

    device, compute_type = resolve_device(device_preset)
    model = WhisperModel(str(model_path), device=device, compute_type=compute_type)
    next_id = (max((seg["id"] for seg in results), default=0) + 1) if results else 1
    total = len(vad_segments)
    for index, vad_seg in enumerate(vad_segments, 1):
        if check_cancel is not None:
            check_cancel()
        if vad_seg["id"] in done_vad_ids:
            if on_progress is not None:
                on_progress(index, total)
            continue
        print(
            f"[asr] {index}/{total} vad={vad_seg['id']} {float(vad_seg['start']):.2f}-{float(vad_seg['end']):.2f}s",
            flush=True,
        )
        chunk_path = work_dir / f"vad_{vad_seg['id']:05d}.wav"
        extract_region(root, audio_path, vad_seg["start"], vad_seg["end"], chunk_path)
        segments, _info = model.transcribe(
            str(chunk_path),
            language="ja",
            task="transcribe",
            vad_filter=False,
            beam_size=5,
        )
        new_segs: list[dict[str, Any]] = []
        chunk_start = float(vad_seg["start"])
        chunk_duration = float(vad_seg["end"]) - chunk_start
        for asr_seg in segments:
            text = asr_seg.text.strip()
            if not text:
                continue
            asr_start = max(0.0, float(asr_seg.start))
            asr_end = float(asr_seg.end)
            # Drop whisper hallucination: on very short or near-silent chunks
            # whisper can emit trailing text ("ご視聴ありがとうございました")
            # with timestamps running far past the chunk boundary, which would
            # overlap all following segments.
            if asr_end > chunk_duration + 1.0 and asr_end > chunk_duration * 2:
                continue
            # Clamp timestamps to the chunk; whisper often overshoots by a few
            # tens of ms, which creates spurious cross-segment overlaps.
            asr_end = min(asr_end, chunk_duration)
            if asr_end <= asr_start:
                continue
            start = chunk_start + asr_start
            end = chunk_start + asr_end
            seg = {
                "id": next_id,
                "start": start,
                "end": end,
                "text": text,
                "speaker": "",
                "vad": {
                    "segment_id": vad_seg["id"],
                    "start": vad_seg["start"],
                    "end": vad_seg["end"],
                },
                "asr": {"avg_logprob": getattr(asr_seg, "avg_logprob", None), "no_speech_prob": None},
                "flags": [],
            }
            new_segs.append(seg)
            results.append(seg)
            next_id += 1
        # Checkpoint: flush this VAD segment's results immediately so an
        # interrupt keeps all already-transcribed text.
        if partial_path is not None and new_segs:
            with partial_path.open("a", encoding="utf-8") as fh:
                for seg in new_segs:
                    fh.write(json.dumps(seg, ensure_ascii=False) + "\n")
        if on_progress is not None:
            on_progress(index, total)
    return results


def resolve_device(preset: str) -> tuple[str, str]:
    if preset == "cpu":
        return "cpu", "int8"
    if preset == "gpu_low_vram":
        return "cuda", "int8_float16"
    if preset == "gpu_quality":
        return "cuda", "float16"
    return "auto", "auto"


def _ensure_cuda_dlls() -> None:
    """Make ctranslate2 find cublas64_12.dll on Windows.

    ctranslate2 4.8.x ships cudnn64_9.dll but not cuBLAS. The nvidia-cublas-cu12
    pip package places cublas64_12.dll under site-packages/nvidia/cublas/bin.
    ctranslate2's C++ side loads it via an unflagged LoadLibrary, which only
    searches PATH, so we must prepend that bin directory to PATH. We also call
    os.add_dll_directory for good measure. No-op on non-Windows or when the
    package is absent (CPU runs keep working).
    """
    import os
    import sys

    if sys.platform != "win32":
        return
    try:
        import importlib.util

        spec = importlib.util.find_spec("nvidia")
        if spec is None or not spec.submodule_search_locations:
            return
        nvidia_root = Path(spec.submodule_search_locations[0])
    except Exception:
        return
    bins: list[str] = []
    for sub in ("cublas", "cuda_nvrtc"):
        bin_dir = nvidia_root / sub / "bin"
        if bin_dir.is_dir():
            bins.append(str(bin_dir))
    if not bins:
        return
    os.environ["PATH"] = os.pathsep.join(bins) + os.pathsep + os.environ.get("PATH", "")
    for bin_dir in bins:
        try:
            os.add_dll_directory(bin_dir)
        except Exception:
            pass
