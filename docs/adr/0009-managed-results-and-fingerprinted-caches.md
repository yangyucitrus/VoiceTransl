# ADR 0009: Managed Results and Fingerprinted Caches

## Status

Accepted

## Context

Completed runs can retain large converted audio files, ASR chunks, partial
checkpoints, and translation workspaces. The previous GUI showed output history
but could neither report this disk use nor remove it. Cache reuse also depended
only on a file being present, so changing transcription intensity, a model,
dictionary, or translation configuration could silently reuse stale artifacts.

Users need to recover disk space and retry only the failed or changed stage
without risking their source media or repeating expensive upstream work.

## Decision

Treat each source-derived `.voicetransl` directory as a managed result.

- Store `manifest.json` at the result root with independent fingerprints for
  audio, VAD, ASR, translation, and quality stages. API keys are never included.
- Reuse a stage only when its fingerprint matches and all required artifacts
  still exist. Legacy outputs without a manifest are recomputed once.
- Safe cleanup removes only converted audio, ASR chunks and partial checkpoints,
  and temporary GalTransl projects. It preserves final SRT, timed Japanese and
  Chinese JSON, quality reports, and the source media.
- Full cache cleanup removes the result's `cache` directory but keeps final SRT.
- Result deletion removes only the validated `.voicetransl` directory. It never
  deletes the corresponding source path.
- Translation retry preserves Japanese transcription and invalidates translation
  plus quality artifacts. Transcription retry preserves converted audio and VAD
  while invalidating ASR and every downstream stage.
- Storage and retry commands cross the existing JSONL worker boundary. The
  worker accepts them only while idle and validates that each output path is the
  exact source-derived `.voicetransl` path before inspecting or deleting it.
- The Flutter result library shows final, cache, and safely reclaimable sizes.
  Every destructive operation requires an explicit scope-specific confirmation.

## Consequences

- Configuration changes can no longer silently reuse incompatible output.
- Users can trade disk space for faster reruns with a clearly defined cleanup
  ladder instead of manually deleting folders.
- Stage retry avoids unnecessary API calls or ASR work while retaining a safe
  invalidation boundary.
- The first rerun of an old result may take longer because untracked legacy
  caches are deliberately treated as stale.
- Fingerprinting model directories adds a small metadata scan before processing;
  this cost is accepted in exchange for deterministic cache validity.
