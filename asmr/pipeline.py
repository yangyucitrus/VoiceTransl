from __future__ import annotations

import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .audio import to_wav_16k_mono
from .config import AppConfig, require_config_ready
from .dictionaries import apply_replacements, load_replacements
from .models import check_model_readiness
from .quality import build_quality_report
from .subtitles import merge_asr_segments, read_json, write_bilingual_srt, write_json, write_srt
from .transcribe import transcribe_regions
from .translate import preflight_api, translate_with_galtransl
from .vad import detect_speech


@dataclass
class FileResult:
    input_path: Path
    status: str
    output_dir: Path
    warnings: int = 0
    error: str | None = None


def output_paths(input_path: Path) -> tuple[Path, Path, str]:
    stem = input_path.stem
    out_dir = input_path.with_suffix("").with_name(f"{stem}.voicetransl")
    cache_dir = out_dir / "cache"
    return out_dir, cache_dir, stem


def process_files(
    config: AppConfig,
    inputs: list[Path],
    transcribe_only: bool,
    no_cache: bool,
    skip_api_preflight: bool,
    limit_segments: int | None = None,
    start_segment: int = 0,
) -> list[FileResult]:
    require_config_ready(config, transcribe_only)
    if not transcribe_only and config.settings["pipeline"].get("preflight_translation_api", True) and not skip_api_preflight:
        ok, message = preflight_api(
            config.settings["translator"]["endpoint"],
            config.settings["translator"]["model"],
            config.api_key or "",
        )
        if not ok:
            raise RuntimeError(message)
        print(f"[preflight] {message}")

    missing = check_model_readiness(config, transcribe_only)
    if missing:
        raise RuntimeError("Model readiness check failed:\n" + "\n".join(missing))

    results: list[FileResult] = []
    for input_path in inputs:
        try:
            results.append(process_one(config, input_path, transcribe_only, no_cache, limit_segments, start_segment))
        except Exception as exc:
            out_dir, cache_dir, _stem = output_paths(input_path)
            cache_dir.mkdir(parents=True, exist_ok=True)
            (cache_dir / "run.log").write_text(traceback.format_exc(), encoding="utf-8")
            results.append(FileResult(input_path, "failed", out_dir, error=str(exc)))
            if not config.settings["pipeline"].get("continue_on_error", True):
                break
    return results


def process_one(config: AppConfig, input_path: Path, transcribe_only: bool, no_cache: bool, limit_segments: int | None = None, start_segment: int = 0) -> FileResult:
    input_path = input_path.resolve()
    out_dir, cache_dir, stem = output_paths(input_path)
    out_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)
    log_lines: list[str] = []

    audio_path = cache_dir / "audio.16k.wav"
    vad_path = cache_dir / "vad_segments.json"
    ja_json_path = cache_dir / f"{stem}.ja.json"
    zh_json_path = cache_dir / f"{stem}.zh.json"
    quality_path = cache_dir / "quality_report.json"

    if no_cache or not audio_path.exists():
        log_lines.append("Converting audio to 16k mono wav")
        to_wav_16k_mono(input_path, audio_path, config.root)

    if no_cache or not vad_path.exists():
        log_lines.append("Running ASMR VAD")
        model_paths = config.settings["models"]
        vad_doc = detect_speech(
            audio_path,
            config.path_from_root(model_paths["whisper_vad_onnx"]),
            config.path_from_root(model_paths["whisper_vad_metadata"]),
            config.settings["vad"]["preset"],
            config.path_from_root(model_paths["whisper_base"]),
        )
        write_json(vad_path, vad_doc)
    else:
        vad_doc = read_json(vad_path)

    if no_cache or not ja_json_path.exists():
        log_lines.append("Running Japanese ASR")
        model_paths = config.settings["models"]
        segments = transcribe_regions(
            config.root,
            audio_path,
            vad_doc,
            config.path_from_root(model_paths["transwithai_whisper_ja"]),
            config.settings["asr"]["device_preset"],
            cache_dir / "asr_chunks",
            cache_dir / "asr_partial.jsonl",
            limit_segments=limit_segments,
            start_segment=start_segment,
        )
        segments = apply_transcription_dictionary(config, segments)
        segments = merge_asr_segments(segments, config.settings["subtitle"]["merge"])
        ja_doc = {
            "schema_version": 1,
            "source": {
                "input_path": str(input_path),
                "audio_path": str(audio_path),
                "language": "ja",
                "duration": None,
            },
            "engine": {
                "asr": config.settings["asr"]["engine"],
                "vad": config.settings["vad"]["preset"],
                "device_preset": config.settings["asr"]["device_preset"],
            },
            "segments": segments,
        }
        write_json(ja_json_path, ja_doc)
        partial_path = cache_dir / "asr_partial.jsonl"
        if partial_path.exists():
            partial_path.unlink()
    else:
        ja_doc = read_json(ja_json_path)

    write_srt(out_dir / f"{stem}.ja.srt", ja_doc["segments"], "text")

    zh_doc = None
    translation_error = None
    status = "transcribe_only" if transcribe_only else "success"
    if not transcribe_only:
        try:
            if no_cache or not zh_json_path.exists():
                log_lines.append("Running GalTransl translation")
                zh_doc = translate_with_galtransl(
                    config.root,
                    cache_dir,
                    stem,
                    ja_doc,
                    config.settings["translator"]["endpoint"],
                    config.settings["translator"]["model"],
                    config.api_key or "",
                    config.settings["translator"]["profile"],
                    config.path_from_root(config.settings["dictionaries"]["translation_glossary"]),
                )
                zh_doc = apply_post_translation_dictionary(config, zh_doc)
                write_json(zh_json_path, zh_doc)
            else:
                zh_doc = read_json(zh_json_path)
            fmt = config.settings["subtitle"]["format"]
            write_srt(out_dir / f"{stem}.zh.srt", zh_doc["segments"], "text", fmt["zh_srt_max_line_chars"])
            write_bilingual_srt(
                out_dir / f"{stem}.combine.srt",
                ja_doc["segments"],
                zh_doc["segments"],
                fmt["combine_srt_ja_max_line_chars"],
                fmt["combine_srt_zh_max_line_chars"],
            )
        except Exception as exc:
            translation_error = str(exc)
            status = "translation_failed"
            log_lines.append(f"Translation failed: {translation_error}")

    report = build_quality_report(ja_doc, zh_doc, translation_error)
    write_json(quality_path, report)
    (cache_dir / "run.log").write_text("\n".join(log_lines) + "\n", encoding="utf-8")
    warnings = len([item for item in report["checks"] if item["severity"] == "warning"])
    return FileResult(input_path, status, out_dir, warnings=warnings, error=translation_error)


def apply_transcription_dictionary(config: AppConfig, segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    pairs = load_replacements(config.path_from_root(config.settings["dictionaries"]["transcription_corrections"]))
    if not pairs:
        return segments
    for seg in segments:
        seg["text"] = apply_replacements(seg["text"], pairs)
    return segments


def apply_post_translation_dictionary(config: AppConfig, zh_doc: dict[str, Any]) -> dict[str, Any]:
    pairs = load_replacements(config.path_from_root(config.settings["dictionaries"]["post_translation_replacements"]))
    if not pairs:
        return zh_doc
    for seg in zh_doc.get("segments", []):
        seg["text"] = apply_replacements(seg["text"], pairs)
    return zh_doc


def run_smoke_test(root: Path) -> Path:
    smoke_dir = root / "runtime" / "smoke"
    cache_dir = smoke_dir / "sample.voicetransl" / "cache"
    out_dir = smoke_dir / "sample.voicetransl"
    stem = "sample"
    ja_doc = {
        "schema_version": 1,
        "source": {"input_path": "sample.wav", "audio_path": "cache/audio.16k.wav", "language": "ja", "duration": 5.0},
        "engine": {"asr": "smoke", "vad": "standard_asmr", "device_preset": "cpu"},
        "segments": [
            {"id": 1, "start": 0.5, "end": 2.0, "text": "お兄ちゃん、こっち来て", "speaker": "", "vad": {"segment_id": 1, "start": 0.4, "end": 2.1}, "asr": {}, "flags": []},
            {"id": 2, "start": 2.4, "end": 4.0, "text": "耳元で、そっと話すね", "speaker": "", "vad": {"segment_id": 2, "start": 2.3, "end": 4.1}, "asr": {}, "flags": []},
        ],
    }
    zh_doc = {
        "schema_version": 1,
        "source_ja_json": "cache/sample.ja.json",
        "translator": {"backend": "smoke", "endpoint": "none", "model": "none", "profile": "ASMR_Adult_2D.md"},
        "segments": [
            {"id": 1, "start": 0.5, "end": 2.0, "source_text": "お兄ちゃん、こっち来て", "text": "哥哥，到这边来", "flags": []},
            {"id": 2, "start": 2.4, "end": 4.0, "source_text": "耳元で、そっと話すね", "text": "我会在你耳边轻轻说哦", "flags": []},
        ],
    }
    cache_dir.mkdir(parents=True, exist_ok=True)
    write_json(cache_dir / f"{stem}.ja.json", ja_doc)
    write_json(cache_dir / f"{stem}.zh.json", zh_doc)
    write_srt(out_dir / f"{stem}.ja.srt", ja_doc["segments"], "text")
    write_srt(out_dir / f"{stem}.zh.srt", zh_doc["segments"], "text", 18)
    write_bilingual_srt(out_dir / f"{stem}.combine.srt", ja_doc["segments"], zh_doc["segments"], 24, 18)
    write_json(cache_dir / "quality_report.json", build_quality_report(ja_doc, zh_doc))
    return out_dir
