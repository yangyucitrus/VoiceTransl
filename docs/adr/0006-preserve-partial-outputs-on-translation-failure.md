# ADR 0006: Preserve Partial Outputs on Translation Failure

## Status

Accepted

## Context

The pipeline has two expensive and independently valuable stages: Japanese transcription and Chinese translation. Translation depends on online OpenAI-compatible APIs and can fail for reasons unrelated to transcription quality, such as invalid tokens, endpoint errors, quota limits, or temporary network failures.

Users should not lose a successful Japanese transcription because the translation step failed.

## Decision

If transcription succeeds but translation fails:

- Keep `cache/<stem>.ja.json`.
- Keep `<stem>.ja.srt`.
- Write `quality_report.json` with Japanese checks and a translation failure entry.
- Keep `run.log`.
- Mark the file as `translation_failed` in the final summary.
- Do not create empty or placeholder `<stem>.zh.srt` or `<stem>.combine.srt`.

The next run with cache reuse may skip transcription and retry translation from the existing Japanese timed JSON.

## Consequences

- Users can immediately inspect or use Japanese subtitles even when online translation fails.
- API errors do not waste ASR work.
- The final summary must distinguish `failed`, `translation_failed`, `transcribe_only`, and `success`.
- Output consumers can trust that Chinese and bilingual SRT files exist only when translation actually completed.
