from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def seconds_to_srt(value: float) -> str:
    value = max(0.0, float(value))
    hours = int(value // 3600)
    minutes = int((value % 3600) // 60)
    seconds = int(value % 60)
    millis = int(round((value - int(value)) * 1000))
    if millis == 1000:
        millis = 0
        seconds += 1
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{millis:03d}"


def wrap_text(text: str, max_chars: int, max_lines: int = 2) -> str:
    text = text.strip()
    if max_chars <= 0 or len(text) <= max_chars:
        return text
    lines: list[str] = []
    remaining = text
    while remaining and len(lines) < max_lines:
        if len(remaining) <= max_chars:
            lines.append(remaining)
            remaining = ""
            break
        cut = max_chars
        for mark in ("，", "。", "！", "？", "、", "…", ",", ".", "!", "?"):
            idx = remaining.rfind(mark, 0, max_chars + 1)
            if idx >= max_chars // 2:
                cut = idx + 1
                break
        lines.append(remaining[:cut].strip())
        remaining = remaining[cut:].strip()
    if remaining and lines:
        lines[-1] = (lines[-1] + remaining).strip()
    return "\n".join(line for line in lines if line)


def ja_to_galtransl(ja_doc: dict[str, Any]) -> list[dict[str, Any]]:
    result = []
    for seg in ja_doc.get("segments", []):
        item = {
            "index": seg["id"],
            "start": seg["start"],
            "end": seg["end"],
            "message": seg["text"],
        }
        if seg.get("speaker"):
            item["name"] = seg["speaker"]
        result.append(item)
    return result


def galtransl_to_zh(ja_doc: dict[str, Any], translated: list[dict[str, Any]], translator: dict[str, str]) -> dict[str, Any]:
    ja_segments = ja_doc.get("segments", [])
    zh_segments = []
    for ja_seg, zh_item in zip(ja_segments, translated):
        zh_segments.append(
            {
                "id": ja_seg["id"],
                "start": ja_seg["start"],
                "end": ja_seg["end"],
                "source_text": ja_seg["text"],
                "text": zh_item.get("message", ""),
                "flags": [],
            }
        )
    return {
        "schema_version": 1,
        "source_ja_json": "cache/<stem>.ja.json",
        "translator": translator,
        "segments": zh_segments,
    }


def write_srt(path: Path, segments: list[dict[str, Any]], text_key: str, max_line_chars: int | None = None) -> None:
    lines: list[str] = []
    for idx, seg in enumerate(segments, 1):
        text = str(seg.get(text_key, "")).strip()
        if max_line_chars:
            text = wrap_text(text, max_line_chars)
        lines.extend(
            [
                str(idx),
                f"{seconds_to_srt(seg['start'])} --> {seconds_to_srt(seg['end'])}",
                text,
                "",
            ]
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def write_bilingual_srt(path: Path, ja_segments: list[dict[str, Any]], zh_segments: list[dict[str, Any]], ja_chars: int, zh_chars: int) -> None:
    lines: list[str] = []
    for idx, (ja_seg, zh_seg) in enumerate(zip(ja_segments, zh_segments), 1):
        ja_text = wrap_text(str(ja_seg.get("text", "")).strip(), ja_chars, max_lines=1)
        zh_text = wrap_text(str(zh_seg.get("text", "")).strip(), zh_chars, max_lines=2)
        lines.extend(
            [
                str(idx),
                f"{seconds_to_srt(ja_seg['start'])} --> {seconds_to_srt(ja_seg['end'])}",
                ja_text,
                zh_text,
                "",
            ]
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def merge_asr_segments(segments: list[dict[str, Any]], merge_settings: dict[str, Any]) -> list[dict[str, Any]]:
    if not segments:
        return []
    merged: list[dict[str, Any]] = []
    current = dict(segments[0])
    current["source_segment_ids"] = [segments[0]["id"]]

    for candidate in segments[1:]:
        if should_merge(current, candidate, merge_settings):
            current["end"] = candidate["end"]
            current["text"] = (current["text"].rstrip() + candidate["text"].lstrip()).strip()
            current["source_segment_ids"].append(candidate["id"])
            current.setdefault("flags", [])
            if current.get("vad", {}).get("segment_id") != candidate.get("vad", {}).get("segment_id"):
                current["flags"].append("cross_vad_merge")
        else:
            merged.append(current)
            current = dict(candidate)
            current["source_segment_ids"] = [candidate["id"]]
    merged.append(current)

    min_duration = merge_settings.get("min_segment_duration_ms", 0) / 1000
    for idx, seg in enumerate(merged):
        duration = seg["end"] - seg["start"]
        if duration < min_duration:
            desired_end = seg["start"] + min_duration
            next_start = merged[idx + 1]["start"] if idx + 1 < len(merged) else None
            if next_start is None or desired_end <= next_start:
                seg["end"] = desired_end

    for idx, seg in enumerate(merged, 1):
        seg["id"] = idx
    return merged


def should_merge(left: dict[str, Any], right: dict[str, Any], settings: dict[str, Any]) -> bool:
    gap_ms = (right["start"] - left["end"]) * 1000
    same_vad = left.get("vad", {}).get("segment_id") == right.get("vad", {}).get("segment_id")
    max_gap = settings["same_vad_max_gap_ms"] if same_vad else settings["cross_vad_max_gap_ms"]
    if gap_ms < 0 or gap_ms > max_gap:
        return False
    duration_ms = (right["end"] - left["start"]) * 1000
    if duration_ms > settings["max_segment_duration_ms"]:
        return False
    text = (left.get("text", "") + right.get("text", "")).strip()
    if len(text) > settings["max_ja_chars"]:
        return False
    return True
