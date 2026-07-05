$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $Root ".venv\Scripts\python.exe"

if (!(Test-Path $Python)) {
    python -m venv (Join-Path $Root ".venv")
}

$env:PIP_CACHE_DIR = Join-Path $Root ".cache\pip"
$env:HF_HOME = Join-Path $Root ".cache\huggingface"
$env:TRANSFORMERS_CACHE = Join-Path $Root ".cache\huggingface\transformers"

& $Python -m pip install --upgrade pip
& $Python -m pip install -r (Join-Path $Root "requirements-asmr.txt")

New-Item -ItemType Directory -Force -Path (Join-Path $Root "models\transwithai-whisper-ja-1.5b-ct2") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Root "models\whisper-vad-asmr-onnx") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Root "models\whisper-base") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Root "runtime\whisper-vad") | Out-Null

Write-Host "Local runtime ready under $Root"
