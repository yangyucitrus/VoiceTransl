from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


def find_ffmpeg(root: Path) -> str:
    candidates = [
        root / "runtime" / "ffmpeg" / "ffmpeg.exe",
        root / "ffmpeg" / "ffmpeg.exe",
        root.parent / "_internal" / "ffmpeg" / "ffmpeg.exe",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    found = shutil.which("ffmpeg")
    if found:
        return found
    raise RuntimeError("ffmpeg not found. Put ffmpeg.exe under runtime/ffmpeg/ or ffmpeg/.")


def to_wav_16k_mono(input_path: Path, output_path: Path, root: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    ffmpeg = find_ffmpeg(root)
    cmd = [
        ffmpeg,
        "-y",
        "-i",
        str(input_path),
        "-vn",
        "-ac",
        "1",
        "-ar",
        "16000",
        str(output_path),
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
