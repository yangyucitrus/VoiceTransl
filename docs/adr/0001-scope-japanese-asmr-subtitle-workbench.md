# ADR 0001: Scope This Fork as a Japanese ASMR Subtitle Workbench

## Status

Accepted

## Context

The upstream application is a broad all-in-one tool for downloading, audio extraction, transcription, translation, media synthesis, summarization, and miscellaneous utilities. This fork is intended to solve a narrower quality problem: Japanese ASMR/adult voice transcription and subtitles have poor timing, insufficient VAD integration, and translation prompts that do not match the desired subtitle style.

Trying to preserve every upstream feature would keep the implementation large and make the first quality pass hard to stabilize.

## Decision

This fork will prioritize a Japanese ASMR subtitle workbench.

In v1, keep:

- Local audio/video file input.
- Japanese ASMR transcription using TransWithAI-oriented ASR/VAD.
- OpenAI-compatible online translation through GalTransl-compatible JSON.
- Three dictionary stages: transcription correction, translation glossary, and post-translation replacement.
- Japanese SRT, Chinese SRT, bilingual SRT, transcription JSON, translation JSON, logs, caches, and quality reports.
- Batch processing in serial order.
- A compact multi-tab UI after the CLI core is stable.

In v1, remove or defer:

- Link downloading.
- General multilingual transcription.
- Generic Whisper model marketplace.
- Local Sakura/GalTransl translation model management.
- Direct Chinese ASR translation mode.
- Media cutting, vocal separation, video/audio synthesis, and summarization.
- PyInstaller packaging.

## Consequences

- The implementation can optimize defaults for Japanese ASMR instead of general media.
- The first stable core can be built as a CLI pipeline before reintroducing a thin PyQt UI.
- Users who need the broader toolbox can keep using upstream VoiceTransl.
- Future features must justify themselves against subtitle quality, repeatability, or workflow speed.

