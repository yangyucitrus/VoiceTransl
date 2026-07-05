from __future__ import annotations

from typing import Any


def check_segments(doc: dict[str, Any], text_key: str, language: str) -> list[dict[str, Any]]:
    warnings: list[dict[str, Any]] = []
    prev_end = 0.0
    seen: dict[str, int] = {}
    for seg in doc.get("segments", []):
        seg_id = seg.get("id")
        start = float(seg.get("start", 0))
        end = float(seg.get("end", 0))
        text = str(seg.get(text_key, "")).strip()
        if not text:
            warnings.append({"severity": "error", "segment_id": seg_id, "code": "empty_text"})
        if end <= start:
            warnings.append({"severity": "error", "segment_id": seg_id, "code": "bad_timestamp"})
        if start < prev_end:
            warnings.append({"severity": "error", "segment_id": seg_id, "code": "overlap"})
        if end - start > 8:
            warnings.append({"severity": "warning", "segment_id": seg_id, "code": "long_segment"})
        if text:
            seen[text] = seen.get(text, 0) + 1
            if seen[text] >= 3:
                warnings.append({"severity": "warning", "segment_id": seg_id, "code": "repeated_text"})
        if language == "zh" and any("\u3040" <= char <= "\u30ff" for char in text):
            warnings.append({"severity": "warning", "segment_id": seg_id, "code": "leftover_japanese"})
        prev_end = max(prev_end, end)
    return warnings


def build_quality_report(
    ja_doc: dict[str, Any] | None,
    zh_doc: dict[str, Any] | None = None,
    translation_error: str | None = None,
) -> dict[str, Any]:
    report: dict[str, Any] = {"schema_version": 1, "status": "ok", "checks": []}
    if ja_doc is not None:
        report["checks"].extend(check_segments(ja_doc, "text", "ja"))
    if zh_doc is not None:
        report["checks"].extend(check_segments(zh_doc, "text", "zh"))
    if translation_error:
        report["checks"].append(
            {"severity": "error", "code": "translation_failed", "message": translation_error}
        )
    if any(item["severity"] == "error" for item in report["checks"]):
        report["status"] = "error"
    elif report["checks"]:
        report["status"] = "warning"
    return report
