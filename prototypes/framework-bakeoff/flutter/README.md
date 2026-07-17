# VoiceTransl Flutter Study

Bright native Windows shell for the VoiceTransl ASMR transcription workflow.
It uses a real Flutter widget tree and runs the existing Python pipeline as a
supervised local worker process. It does not use a browser or WebView.

## Design Direction

- Light, quiet workbench layout inspired by Codex desktop ergonomics.
- Sakura pink for primary actions, cyan for running state, and neutral surfaces.
- Original chibi audio assistant used as a supporting asset, not the main UI.
- Task queue, transcript preview, recent outputs, runtime state, and active
  configuration are visible in the first viewport.
- The assistant panel folds away below the wide desktop breakpoint.

## Verification

```powershell
flutter analyze
flutter test
flutter test --update-goldens test\screenshot_test.dart
```

The checked-in reference render is
`test/goldens/flutter-light-workbench.png` at 1280x800.

## Python Worker

During development the app walks up from its working directory, finds
`asmr_worker.py`, and starts it with the repository `.venv`. Packaged builds
look for `backend/voicetransl-worker.exe` beside the Flutter executable. These
paths can be overridden with `VOICETRANSL_WORKER` and `VOICETRANSL_PYTHON`.

The worker uses newline-delimited JSON over stdin/stdout. The first connected
slice supports native file selection, directory scanning, transcription-only
runs, structured stage progress, safe cancellation, result reporting, and
opening the output directory.

Run a protocol smoke test without Flutter:

```powershell
@('{"command":"ping","request_id":"smoke"}',
  '{"command":"shutdown"}') |
  .\.venv\Scripts\python.exe -u asmr_worker.py
```

Building the Windows executable requires Visual Studio with the Desktop
development with C++ workload. The UI can still be rendered and tested with
Flutter's native test renderer before that toolchain is installed.

## GitHub Actions Build

The `Flutter Windows GUI` workflow builds the native Windows release on a
GitHub-hosted runner and uploads `VoiceTransl-Windows-x64`. It intentionally
contains only the Flutter runtime; the local Python environment and models stay
in the repository.

From the repository root, run `update_gui.cmd` to download the latest successful
artifact for the current branch into `runtime/flutter-windows`. Then run
`start_gui.cmd` to launch the GUI with the repository `.venv`, `asmr_worker.py`,
and `models/` directory.
