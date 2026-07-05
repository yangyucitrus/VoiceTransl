# ADR 0003: Use Preset-Driven Configuration

## Status

Accepted

## Context

Japanese ASMR transcription quality depends on several low-level ASR and VAD parameters. Exposing every parameter in the GUI would make the app harder to use and would encourage trial-and-error tuning before the baseline workflow is stable.

The v1 goal is text accuracy first, with stable usable timestamps. The implementation still needs access to concrete VAD and device settings, but users should mainly choose intent-level presets.

## Decision

Use `settings.yaml` as the shared configuration contract for the CLI and future GUI. The GUI exposes only approved choices:

- ASR engine preset: `transwithai_whisper_ja`, with `sherpa_ja` reserved for experimental comparison.
- VAD preset: `standard_asmr`, `whisper_sensitive`, `clean_conservative`.
- Device preset: `auto`, `gpu_quality`, `gpu_low_vram`, `cpu`.

Raw VAD values and ASR compute details are resolved inside the pipeline from these presets. Advanced values may exist internally, but v1 does not expose them as GUI controls.

Secrets stay out of `settings.yaml`. `.env` stores `VOICETRANSL_API_KEY`; endpoint, model, translation profile, presets, cache behavior, dictionary paths, and model paths live in `settings.yaml`.

## Consequences

- The product has stable defaults for Japanese ASMR instead of becoming a generic ASR parameter panel.
- CLI and GUI behavior stay aligned because both load the same settings contract.
- Users can switch between meaningful profiles without understanding every VAD threshold.
- Future expert mode remains possible, but it is not part of v1.
