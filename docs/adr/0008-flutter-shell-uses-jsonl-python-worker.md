# ADR 0008: Flutter Shell Uses a Supervised JSONL Python Worker

## Status

Accepted

## Context

Flutter was selected for the native Windows desktop shell after the Qt,
Avalonia, and Slint visual studies. The ASMR pipeline, model loading,
translation integration, dictionaries, cache contract, and cancellation
boundaries already live in Python. Embedding Python inside the Flutter process
or porting the pipeline to Dart would create a large new failure surface.

The desktop shell needs a small integration boundary that works during local
development and can later be packaged without coupling Flutter to PySide6.

## Decision

Run the Python pipeline as one supervised child process and communicate over
newline-delimited JSON on standard input and output.

- `asmr_worker.py` is the development entrypoint.
- `asmr.worker_protocol.WorkerServer` owns protocol validation and request state.
- Standard output is reserved for JSONL protocol messages; ordinary Python and
  library output is redirected to standard error.
- Protocol version 1 supports `ping`, `run`, `cancel`, and `shutdown` commands.
- Pipeline events are forwarded without changing their existing payload shape.
- Only one pipeline request runs at a time. Cancellation uses the existing safe
  pipeline checks rather than terminating the process immediately.
- Native NumPy/ONNX VAD dependencies are initialized on the worker main thread
  before the `ready` message. This avoids Windows native-loader deadlocks caused
  by first importing OpenBLAS-backed modules inside the pipeline thread.
- VAD inference reports progress and checks cancellation after each 30-second
  audio chunk instead of presenting the whole stage as one opaque operation.
- Flutter combines structured pipeline events and worker stderr into a bounded,
  timestamped live log that remains readable while a task is running.
- The first connected GUI slice runs transcription-only with cache reuse and no
  translation API preflight.
- Development discovery prefers `.venv/Scripts/python.exe`; packaged discovery
  prefers `backend/voicetransl-worker.exe`. Environment variables can override
  both paths.

## Consequences

- Flutter can remain a native presentation and interaction layer.
- The Python pipeline remains the single owner of ASR, translation, and output
  behavior.
- Worker crashes and protocol errors can be shown as task failures instead of
  crashing the GUI.
- Slow initialization and long-running stages are visible rather than appearing
  frozen at a stage boundary.
- The worker can be tested with injected pipeline runners, while Flutter can
  test task state with a fake transport.
- Distribution is a multi-file application inside one installer, not a single
  monolithic executable.
- Translation settings, dictionaries, transcript editing, and packaged worker
  creation remain later integration slices.
