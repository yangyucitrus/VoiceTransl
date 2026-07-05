# Local Runtime and Model Layout

The ASMR pipeline keeps runtime state inside the project folder.

## Python Environment

Use a project-local virtual environment:

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install --upgrade pip
.\.venv\Scripts\python -m pip install -r requirements-asmr.txt
```

Or run the project helper:

```powershell
.\scripts\setup_local_runtime.ps1
```

Do not install dependencies globally and do not use a shared user-site package directory.

Copy `settings.example.yaml` to `settings.yaml` for local edits. Runtime secrets stay in `.env`.

## Cache Directories

Pip cache and Hugging Face cache should stay inside the project when downloading models:

```powershell
$env:PIP_CACHE_DIR = "$PWD\.cache\pip"
$env:HF_HOME = "$PWD\.cache\huggingface"
$env:TRANSFORMERS_CACHE = "$PWD\.cache\huggingface\transformers"
```

## Models

Large model files are placed manually or downloaded into `models/`:

```text
models/
  transwithai-whisper-ja-1.5b-ct2/
    config.json
    model.bin
    preprocessor_config.json
    tokenizer.json
    vocabulary.json
  whisper-vad-asmr-onnx/
    model.onnx
    model_metadata.json
  whisper-base/
  sherpa-ja/
```

The GUI should only report readiness and paths in v1. It should not scatter model files into the user profile or system drive.

Use this readiness check:

```powershell
.\.venv\Scripts\python.exe asmr_pipeline.py --check-models --transcribe-only
```
