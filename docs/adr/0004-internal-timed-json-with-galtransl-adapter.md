# ADR 0004: Use Internal Timed JSON with a GalTransl Adapter

## Status

Accepted

## Context

The original repository uses a simple GalTransl-compatible JSON shape with `start`, `end`, and `message`. That shape is useful for translation and SRT conversion, but it is too weak for the new ASMR pipeline. The pipeline needs to preserve source metadata, ASR/VAD preset information, VAD segment provenance, optional ASR confidence fields, quality flags, and a stable segment id.

At the same time, v1 should not rewrite GalTransl. GalTransl remains the online translation adapter for OpenAI-compatible APIs.

## Decision

Use internal timed JSON as the canonical cache format:

- `cache/<stem>.ja.json` stores Japanese transcription segments with `id`, `start`, `end`, `text`, optional `speaker`, VAD provenance, optional ASR metadata, and quality flags.
- `cache/<stem>.zh.json` stores Chinese translation segments with matching `id`, timing, `source_text`, translated `text`, translator metadata, and quality flags.

Only the GalTransl adapter writes temporary GalTransl-compatible JSON:

```json
[
  {
    "start": 12.34,
    "end": 15.67,
    "message": "日文原文"
  }
]
```

After GalTransl finishes, the adapter normalizes its output back into the internal Chinese timed JSON schema. Public SRT files are generated from internal JSON, not from temporary GalTransl files.

## Consequences

- Quality reporting can reason about stable ids, source text, translated text, timings, and pipeline metadata.
- The pipeline can keep ASR/VAD debugging information without leaking it into GalTransl.
- Future adapters, including possible sherpa-onnx timing experiments, can target the same internal segment schema.
- GalTransl remains replaceable because it is contained at an adapter boundary.
