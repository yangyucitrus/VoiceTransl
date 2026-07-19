# ADR 0007: Preflight Translation API Before Full Pipeline Runs

## Status

Accepted

## Context

The default workflow runs transcription and translation. ASR can be slow and expensive in local compute time, while online translation can fail immediately because of missing API keys, bad endpoints, model names, authorization errors, quota limits, or provider outages.

The original workflow surfaced authorization failures during API testing. The new pipeline should avoid running a long transcription job when the requested full pipeline cannot translate.

## Decision

When running the default full pipeline:

- Load `.env` and require `VOICETRANSL_API_KEY`.
- Validate the configured OpenAI-compatible endpoint and model before ASR starts using both a lightweight model-list/authentication check and a minimal text-generation probe.
- Require the generation probe to return a successful response with non-empty assistant text.
- Fail on clear authentication errors such as `401` or `403`.
- If a standard model list is returned, verify the configured model when possible.
- If the provider does not support a standard model-list endpoint, retain the warning but allow the run only when the generation probe succeeds.
- Apply provider-specific compatibility fields consistently to both the generation probe and GalTransl requests. The official DeepSeek endpoint runs subtitle translation with thinking disabled so reasoning tokens cannot consume the output budget or leave the final content empty.
- Retry transient connection/read failures, `408`, `425`, `429`, and common `5xx` responses up to three attempts with bounded exponential backoff. Do not retry clear authentication or request errors.
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
- Full pipeline startup has a model-list request and one very small generation request before local processing begins.
- A temporarily slow provider can add up to two retry delays before startup, but a single latency spike no longer fails the whole batch.
- DeepSeek V4 subtitle translation uses non-thinking mode, which is faster and more predictable for structured batch translation.
- The CLI and future GUI need clear error messages for missing key, authorization failure, endpoint failure, and model validation failure.
- Advanced CLI users can bypass broken model-list endpoints without changing the default GUI experience.
