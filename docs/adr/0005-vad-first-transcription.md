# ADR 0005: Use VAD-First Transcription

## Status

Accepted

## Context

Japanese ASMR and adult voice works often contain long pauses, whispering, quiet breaths, soft speech, and extended low-volume sections. Whole-audio ASR can drift, hallucinate across silence, and produce unstable timestamps in this content style.

The project goal is text accuracy first, with stable usable timestamps. VAD is therefore part of the transcription path, not only a later cleanup step.

## Decision

The stable v1 transcription path is VAD-first:

1. Convert the input media to `cache/audio.16k.wav`.
2. Run the ASMR VAD model and write `cache/vad_segments.json`.
3. Transcribe each detected VAD speech region with `TransWithAI/whisper-ja-1.5B-ct2` using `task=transcribe`.
4. Rebase ASR timestamps from local chunk time to the original media timeline.
5. Merge adjacent ASR results into subtitle-friendly segments.
6. Write the final Japanese internal timed JSON to `cache/<stem>.ja.json`.

Whole-audio ASR with VAD used only as a timestamp post-processor is not the main v1 path. It can be revisited later as an experiment if the VAD-first path fails on specific examples.

VAD regions are ASR processing units, not final subtitle units. Whisper VAD produces frame-level speech probabilities that are post-processed into speech regions; those regions answer "where is speech?" rather than "what should one subtitle line be?" The pipeline therefore keeps VAD regions as provenance and merges subtitle segments only after ASR has produced timestamped text.

Subtitle merging is conservative by default:

- Merge short-gap adjacent ASR segments.
- Avoid crossing clear long silence.
- Prefer not to cross VAD region boundaries.
- Permit crossing a VAD boundary only when two neighboring VAD regions are separated by a very short gap and look like one sentence split by VAD.
- Reject merges that would produce overlong text or overlong display duration.
- Preserve final segment ids for one-to-one Japanese and Chinese alignment.

The default v1 merge thresholds are conservative: merge gaps up to `350ms` inside the same VAD region, merge gaps up to `150ms` across neighboring VAD regions, cap merged subtitles at `6000ms`, avoid Japanese subtitles over `42` characters and Chinese subtitles over `32` characters, and extend very short subtitles to at least `500ms` only when that does not overlap the next segment.

SRT formatting is separate from merge decisions. Chinese SRT and bilingual SRT may wrap long lines deterministically, but Japanese-only SRT should not force wrapping in v1. Default formatting caps are `18` Chinese characters per line, `24` Japanese characters per line in bilingual output, and at most `2` lines for a single-language cue.

## Consequences

- Long files become easier to cache and resume because VAD regions are explicit artifacts.
- Timestamp drift is reduced because ASR operates on shorter speech-focused regions.
- Failure reporting can identify a specific VAD region or ASR chunk.
- Segment merging becomes a first-class part of subtitle generation.
- The pipeline must carefully preserve original timeline offsets when rebasing chunk-level ASR results.
- Quality reporting can use raw VAD regions and probability statistics to flag low-confidence or untranscribed speech regions.
