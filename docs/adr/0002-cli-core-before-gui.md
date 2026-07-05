# ADR 0002: Build the ASMR Pipeline as a CLI Core Before GUI

## Status

Accepted

## Context

The current PyQt entrypoint is large and mixes UI, config migration, subprocess orchestration, translation setup, logs, and media utilities. The v1 scope introduces heavier ASR/VAD dependencies and a new output/cache contract. Building this directly into the GUI would make debugging and testing harder.

## Decision

Build a CLI-first core named `asmr_pipeline.py`, backed by a small `asmr/` package. The PyQt UI will later become a thin shell around this core.

The CLI is the first supported execution surface:

```bash
python asmr_pipeline.py input1.mp3 input2.mp4
python asmr_pipeline.py input.mp3 --transcribe-only
python asmr_pipeline.py input.mp3 --no-cache
python asmr_pipeline.py input.mp3 --settings settings.yaml
```

Core modules:

- `asmr.config`
- `asmr.models`
- `asmr.audio`
- `asmr.vad`
- `asmr.transcribe`
- `asmr.translate`
- `asmr.subtitles`
- `asmr.dictionaries`
- `asmr.quality`
- `asmr.pipeline`

Translation will not rewrite GalTransl in v1. Instead, the pipeline creates a temporary GalTransl project inside each output cache, writes `gt_input/<stem>.json`, configures OpenAI-compatible translation, runs `GalTransl.__main__.worker`, and normalizes `gt_output/<stem>.json` back to `<stem>.zh.json`.

## Consequences

- The ASMR pipeline can be tested without launching PyQt.
- The GUI can be redesigned after the workflow is stable.
- GalTransl internals stay mostly untouched in v1.
- The new pipeline has a clear interface for future sherpa-onnx experiments and quality reporting.

