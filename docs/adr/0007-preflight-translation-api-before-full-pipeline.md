# ADR 0007: Preflight Translation API Before Full Pipeline Runs

## Status

Accepted

## Context

The default workflow runs transcription and translation. ASR can be slow and expensive in local compute time, while online translation can fail immediately because of missing API keys, bad endpoints, model names, authorization errors, quota limits, or provider outages.

The original workflow surfaced authorization failures during API testing. The new pipeline should avoid running a long transcription job when the requested full pipeline cannot translate.

## Decision

When running the default full pipeline:

- Load `.env` and require `VOICETRANSL_API_KEY`.
- Validate the configured OpenAI-compatible endpoint and model before ASR starts using a lightweight model-list/authentication check.
- Do not send a real translation prompt during preflight.
- Fail on clear authentication errors such as `401` or `403`.
- If a standard model list is returned, verify the configured model when possible.
- If the provider does not support a standard model-list endpoint but authentication has not clearly failed, warn and allow the run to continue.
- Stop with an actionable configuration error if API validation fails.

When running `--transcribe-only`:

- Do not require `VOICETRANSL_API_KEY`.
- Do not run translation API validation.

When running `--skip-api-preflight`:

- Skip the model-list/authentication preflight.
- Still require `VOICETRANSL_API_KEY` before translation.
- Do not expose this option in the v1 GUI.

The preflight behavior is controlled by `pipeline.preflight_translation_api: true` in `settings.yaml`.

## Consequences

- Users do not spend time on ASR only to discover a missing or invalid translation token afterward.
- Transcription-only runs remain useful offline.
- Full pipeline startup has one extra API check before local processing begins.
- The CLI and future GUI need clear error messages for missing key, authorization failure, endpoint failure, and model validation failure.
- Advanced CLI users can bypass broken model-list endpoints without changing the default GUI experience.
