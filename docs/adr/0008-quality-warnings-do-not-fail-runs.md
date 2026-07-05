# ADR 0008: Quality Warnings Do Not Fail Runs

## Status

Accepted

## Context

The quality report is intended to surface likely subtitle problems such as long segments, repeated text, leftover Japanese, suspicious silence gaps, and untranscribed VAD regions. These checks are useful but not always definitive, especially for ASMR content where long pauses, breaths, repetitions, and soft vocalizations are common.

## Decision

Quality warnings do not fail a file or change the CLI exit code by themselves.

Structural errors do fail the current file:

- Empty transcription when transcription was requested.
- Invalid, reversed, or overlapping timestamps that cannot be repaired.
- Malformed internal JSON.
- GalTransl output that cannot be parsed or aligned back to Japanese segment ids.
- Missing required output after a step claims success.

The final summary distinguishes clean success from success with warnings.

## Consequences

- Users still receive useful subtitles when deterministic checks are uncertain.
- Quality issues remain visible in `quality_report.json` and the final summary.
- Automation can treat structural failures as failures while allowing advisory warnings.
