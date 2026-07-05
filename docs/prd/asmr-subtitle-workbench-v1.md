# PRD: Japanese ASMR Subtitle Workbench v1

## Summary

Build a focused workflow for local Japanese ASMR/adult voice audio and video files:

`input file -> 16k mono wav -> ASMR VAD -> Japanese transcription -> transcription JSON/SRT -> online translation -> Chinese JSON/SRT -> bilingual SRT -> quality report`

The first implementation should prioritize a testable CLI core. The GUI should become a thin multi-tab shell around the same pipeline.

## Goals

- Improve Japanese ASMR transcription accuracy and stabilize subtitle timing.
- Keep transcription JSON and translation JSON as first-class reusable artifacts.
- Preserve the existing GalTransl JSON translation path, but only with OpenAI-compatible online APIs in v1.
- Provide a translation style tuned for natural adult-oriented Chinese subtitles with moderate 2D/anime tone.
- Support serial batch processing with cache reuse and per-file logs.

## Non-Goals

- No link downloading.
- No general multilingual transcription mode.
- No generic model picker beyond the approved presets.
- No Sakura/local translation model support in v1.
- No direct speech-to-Chinese mode in v1.
- No cutting, vocal separation, media synthesis, summarization, LRC, or VTT in v1.
- No PyInstaller packaging in v1.

## Pipeline Requirements

- Provide a CLI entrypoint named `asmr_pipeline.py`.
- CLI examples:
  - `python asmr_pipeline.py input1.mp3 input2.mp4`
  - `python asmr_pipeline.py input.mp3 --transcribe-only`
  - `python asmr_pipeline.py input.mp3 --no-cache`
  - `python asmr_pipeline.py input.mp3 --settings settings.yaml`
  - `python asmr_pipeline.py input.mp3 --skip-api-preflight`
- Accept local audio/video files such as `.wav`, `.mp3`, `.flac`, `.m4a`, `.aac`, `.ogg`, `.mp4`, `.mkv`, `.mov`, and `.avi`.
- Create output beside the input file in `<stem>.voicetransl/`.
- Store public outputs at the output root:
  - `<stem>.ja.srt`
  - `<stem>.zh.srt`
  - `<stem>.combine.srt`
- Store reusable artifacts under `cache/`:
  - `audio.16k.wav`
  - `vad_segments.json`
  - `<stem>.ja.json`
  - `<stem>.zh.json`
  - `quality_report.json`
  - `run.log`
- Reuse existing cache by default and skip completed steps.
- Process multiple files serially. If one file fails, log it and continue with the next file.
- If `settings.yaml` is missing, generate a default template and stop with a configuration message.
- If default full pipeline mode is active, validate translation configuration before running ASR.
- If `.env` lacks `VOICETRANSL_API_KEY` or the configured OpenAI-compatible endpoint/model test fails, stop before transcription with an actionable configuration error.
- If `--transcribe-only` is set, skip translation API validation.
- If `--skip-api-preflight` is set, skip the model-list/authentication preflight but still require `VOICETRANSL_API_KEY` for translation.
- If transcription succeeds but translation fails, keep and expose Japanese outputs, `quality_report.json`, and `run.log`.
- Do not write empty or placeholder Chinese/bilingual SRT files when translation fails.
- Mark the file as `translation_failed` in the final summary when Japanese outputs exist but Chinese outputs do not.

## Transcription Requirements

- Default ASR preset: `TransWithAI/whisper-ja-1.5B-ct2` with `task=transcribe`.
- Experimental ASR preset: `sherpa-onnx ja`, used for later timing comparison and not required for the first stable path.
- VAD uses TransWithAI's ASMR Whisper VAD ONNX model.
- The stable v1 transcription path is VAD-first:
  - Run ASMR VAD on `cache/audio.16k.wav`.
  - Save detected speech regions to `cache/vad_segments.json`.
  - Transcribe each VAD speech region with the Japanese ASR preset.
  - Rebase segment timestamps to the original media timeline.
  - Merge adjacent ASR results into subtitle-friendly segments.
  - Write the merged result to the internal `cache/<stem>.ja.json` schema.
- Do not use whole-audio ASR with VAD only as a timestamp post-processor for the main v1 path.
- Treat VAD speech regions as ASR processing units, not final subtitle units.
- Subtitle merging happens on ASR output segments after timestamp rebasing.
- Preserve raw VAD regions and probability statistics in `cache/vad_segments.json` for debugging and quality reporting.
- VAD UI exposes only presets:
  - `standard_asmr`
  - `whisper_sensitive`
  - `clean_conservative`
- Advanced VAD values may exist in `settings.yaml`, but the GUI should not expose raw knobs in v1.
- ASR device presets:
  - `auto`
  - `gpu_quality`
  - `gpu_low_vram`
  - `cpu`
- Large models are placed manually under `models/`; v1 only detects missing files and shows links.

## Configuration Requirements

Use a preset-driven `settings.yaml` so the CLI and GUI share one product contract:

```yaml
asr:
  engine: transwithai_whisper_ja
  device_preset: auto

vad:
  preset: standard_asmr

pipeline:
  reuse_cache: true
  continue_on_error: true
  transcribe_only: false
  preflight_translation_api: true

subtitle:
  merge:
    same_vad_max_gap_ms: 350
    cross_vad_max_gap_ms: 150
    max_segment_duration_ms: 6000
    min_segment_duration_ms: 500
    max_ja_chars: 42
    max_zh_chars: 32
  format:
    zh_srt_max_line_chars: 18
    combine_srt_ja_max_line_chars: 24
    combine_srt_zh_max_line_chars: 18
    max_lines: 2

translator:
  endpoint: https://api.deepseek.com
  model: deepseek-v4-flash
  profile: ASMR_Adult_2D.md

models:
  transwithai_whisper_ja: ../models
  whisper_vad_onnx: ../models/whisper_vad.onnx
  whisper_vad_metadata: ../models/whisper_vad_metadata.json
  whisper_base: ../models/whisper-base
  sherpa_ja: ../models/sherpa-ja

dictionaries:
  transcription_corrections: dictionaries/transcription_corrections.txt
  translation_glossary: dictionaries/translation_glossary.txt
  post_translation_replacements: dictionaries/post_translation_replacements.txt

quality:
  enabled: true
```

Preset mappings:

- `standard_asmr`: default VAD profile. Use the TransWithAI/ChickenRice-style baseline: `threshold=0.5`, `min_speech_duration_ms=300`, `min_silence_duration_ms=100`, `speech_pad_ms=200`, segment merge enabled, `max_gap_ms=2000`, `max_duration_ms=20000`, `max_initial_timestamp=30`, `repetition_penalty=1.1`.
- `whisper_sensitive`: low-volume and whisper-friendly VAD profile. Prefer recall over clean segmentation: lower threshold, shorter minimum speech/silence, slightly larger padding, and tolerant segment merge.
- `clean_conservative`: clean-source VAD profile. Prefer fewer false positives: higher threshold, longer minimum speech/silence, moderate padding, and stricter merge.
- `auto`: select the best available ASR device and compute type.
- `gpu_quality`: prefer CUDA quality/speed when VRAM is sufficient.
- `gpu_low_vram`: prefer CUDA with lower memory pressure.
- `cpu`: use CPU fallback.

VAD post-processing should follow the Whisper VAD / Silero-style shape: speech threshold, negative threshold for hysteresis, minimum speech duration, minimum silence duration, speech padding, and optional maximum speech duration. VAD output should include `start`, `end`, `duration`, and available probability statistics such as `avg_prob`, `min_prob`, and `max_prob`.

`.env` stores secrets only:

```dotenv
VOICETRANSL_API_KEY=
```

If `settings.yaml` is missing, the CLI should generate a safe template and stop before processing. If `.env` is missing, the CLI should generate a safe template; full pipeline mode stops until `VOICETRANSL_API_KEY` is configured, while `--transcribe-only` may continue without it.

## Translation Requirements

- Translation uses GalTransl-compatible JSON and OpenAI-compatible online APIs only.
- API key lives in `.env`; endpoint, model, profile, ASR/VAD preset, device preset, and cache settings live in `settings.yaml`.
- Default CLI behavior runs transcription and translation. `--transcribe-only` skips translation.
- Full pipeline mode requires translation API preflight before transcription starts.
- Translation API preflight uses a lightweight model-list/authentication check and must not send a real translation prompt.
- Preflight should fail on clear authentication errors such as `401` or `403`.
- If the provider returns a standard model list, verify the configured model when possible.
- If the provider does not support a standard model-list endpoint but authentication has not clearly failed, warn and allow the run to continue.
- CLI supports `--skip-api-preflight` for providers with broken model-list endpoints. The GUI should not expose this option in v1.
- Translation is implemented by creating a temporary GalTransl project under the file cache and running `GalTransl.__main__.worker(..., "ForGal-json", show_banner=False)`.
- The default translation guideline file is `translation_guidelines/ASMR_Adult_2D.md`.
- Keep three dictionary stages:
  - Transcription correction dictionary.
  - Translation glossary.
  - Post-translation replacement dictionary.
- Automatic correction is conservative and deterministic. Do not use an LLM to rewrite Japanese transcription before translation.
- Default profile: natural adult-oriented Chinese spoken subtitles, faithful, lightly polished, moderate 2D/anime tone, explicit when source is explicit, not vulgarized beyond the source.

## Timed JSON Contract

Use a stronger internal timed JSON schema for reusable cache artifacts. GalTransl-compatible JSON is generated only at translation adapter boundaries.

Japanese transcription cache, `cache/<stem>.ja.json`:

```json
{
  "schema_version": 1,
  "source": {
    "input_path": "input.mp3",
    "audio_path": "cache/audio.16k.wav",
    "language": "ja",
    "duration": 1234.56
  },
  "engine": {
    "asr": "transwithai_whisper_ja",
    "vad": "standard_asmr",
    "device_preset": "auto"
  },
  "segments": [
    {
      "id": 1,
      "start": 12.34,
      "end": 15.67,
      "text": "日文原文",
      "speaker": "",
      "vad": {
        "segment_id": 3,
        "start": 12.1,
        "end": 16.0
      },
      "asr": {
        "avg_logprob": null,
        "no_speech_prob": null
      },
      "flags": []
    }
  ]
}
```

Temporary GalTransl input under the adapter project:

```json
[
  {
    "start": 12.34,
    "end": 15.67,
    "message": "日文原文"
  }
]
```

Chinese translation cache, `cache/<stem>.zh.json`:

```json
{
  "schema_version": 1,
  "source_ja_json": "cache/<stem>.ja.json",
  "translator": {
    "backend": "galtransl",
    "endpoint": "https://api.deepseek.com",
    "model": "deepseek-v4-flash",
    "profile": "ASMR_Adult_2D.md"
  },
  "segments": [
    {
      "id": 1,
      "start": 12.34,
      "end": 15.67,
      "source_text": "日文原文",
      "text": "中文字幕",
      "flags": []
    }
  ]
}
```

SRT outputs are generated from the internal Japanese and Chinese timed JSON, not directly from GalTransl temporary files.

## Subtitle Merge Requirements

VAD regions are not final subtitle segments. They are speech regions used to constrain ASR. The subtitle merge step operates on timestamp-rebased ASR output segments.

Default merge behavior should be conservative:

- Merge adjacent ASR segments when the silence gap is short.
- Keep segments separate across clear long silence.
- Prefer not to cross VAD region boundaries.
- Allow crossing VAD region boundaries only when the regions are separated by a very short gap and look like one sentence split by VAD.
- Do not merge if the resulting subtitle would exceed the configured text length limit.
- Do not merge if the resulting subtitle would exceed the configured duration limit.
- Preserve segment ids after final merge so Japanese and Chinese JSON can align one-to-one.
- Record merge-related flags when a segment is long, crosses a VAD boundary, or is formed from low-confidence VAD regions.

Default v1 merge thresholds:

- `same_vad_max_gap_ms: 350`
- `cross_vad_max_gap_ms: 150`
- `max_segment_duration_ms: 6000`
- `min_segment_duration_ms: 500`
- `max_ja_chars: 42`
- `max_zh_chars: 32`

When enforcing `min_segment_duration_ms`, extend the subtitle end time only when it does not overlap the next segment.

## SRT Formatting Requirements

SRT formatting should be conservative and deterministic:

- Chinese SRT may automatically wrap long lines.
- Bilingual SRT may automatically wrap Chinese lines and may wrap Japanese lines more gently.
- Japanese-only SRT should not force wrapping in v1 unless the source already contains line breaks.
- Do not exceed two lines for a single-language SRT cue.
- For bilingual SRT, prefer one Japanese line plus one or two Chinese lines.
- Do not use an LLM for SRT line wrapping.

Default v1 formatting thresholds:

- `zh_srt_max_line_chars: 18`
- `combine_srt_ja_max_line_chars: 24`
- `combine_srt_zh_max_line_chars: 18`
- `max_lines: 2`

## UI Requirements

Use a compact multi-tab UI after the CLI core is stable:

- Task: files, start/cancel, cache reuse, output summary, progress.
- Transcription: ASR preset, VAD preset, device preset, model readiness.
- Translation: endpoint, model, API key, API test, translation profile.
- Dictionaries/Post-processing: transcription correction, translation glossary, post-translation replacement.
- Logs: detailed log, failed file list, open output folder.

## Implementation Shape

Create a small `asmr/` package instead of adding more pipeline logic to `app.py`:

- `config.py`: load `.env` and `settings.yaml`, generate defaults, validate model readiness.
- `models.py`: ASR/VAD model path checks and preset resolution.
- `audio.py`: ffmpeg conversion to `16kHz` mono wav.
- `vad.py`: TransWithAI ASMR VAD adapter and preset mapping.
- `transcribe.py`: TransWithAI Whisper-ja adapter and sherpa experimental adapter.
- `translate.py`: temporary GalTransl project adapter.
- `subtitles.py`: JSON, SRT, and bilingual SRT read/write.
- `dictionaries.py`: deterministic correction and replacement stages.
- `quality.py`: deterministic quality report generation.
- `pipeline.py`: serial per-file orchestration and cache reuse.

## Quality Report

Generate a lightweight deterministic report for each file:

- Japanese transcription checks: empty text, overlong segment, repeated text, overlapping timestamps, reversed/zero-length timestamps, unusually long silence, and suspiciously untranscribed VAD regions.
- Chinese translation checks: empty translation, leftover Japanese, obviously overlong text, repeated translation, JSON/format errors.
- The report is advisory and should not block output generation unless output is structurally invalid.
- If translation fails after transcription succeeds, still write a quality report containing Japanese checks and a translation failure entry.
- Quality warnings do not make the CLI fail. Structural errors such as empty transcription, invalid timestamps, malformed JSON, or unparseable translation output fail the current file.
- The final summary should distinguish clean success from success with warnings.

## Acceptance Criteria

- A local Japanese ASMR audio/video file can produce `.ja.srt`, `.zh.srt`, `.combine.srt`, `.ja.json`, `.zh.json`, and `quality_report.json`.
- Re-running the same file with cache reuse skips completed steps.
- Multiple files run serially and failures are summarized at the end.
- Missing ASR/VAD models are detected before processing and produce actionable messages.
- `--transcribe-only` produces Japanese outputs and skips API translation.
- Online translation uses the configured OpenAI-compatible endpoint and does not require any local translation model.
- Translation failure after successful transcription still leaves `.ja.srt`, `.ja.json`, `quality_report.json`, and `run.log`.
- Translation failure does not create empty `.zh.srt` or `.combine.srt` files.
- Full pipeline mode stops before ASR when the translation API key or endpoint/model validation fails.
- `--transcribe-only` does not require a translation API key.
- Quality warnings are reported but do not change a successful file into a failed file.
