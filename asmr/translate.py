from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .subtitles import galtransl_to_zh, ja_to_galtransl, read_json, write_json
from .yaml_compat import safe_dump


def normalize_endpoint(endpoint: str) -> str:
    endpoint = endpoint.rstrip("/")
    if endpoint.endswith("/chat/completions"):
        return endpoint.rsplit("/chat/completions", 1)[0]
    return endpoint[:-3] if endpoint.endswith("/v1") else endpoint


def preflight_api(endpoint: str, model: str, api_key: str) -> tuple[bool, str]:
    try:
        import requests
    except Exception as exc:
        return False, f"requests is not installed: {exc}"
    url = normalize_endpoint(endpoint) + "/v1/models"
    try:
        response = requests.get(url, headers={"Authorization": f"Bearer {api_key}"}, timeout=20)
    except requests.RequestException as exc:
        return False, f"API preflight failed: {exc}"
    if response.status_code in (401, 403):
        return False, f"API authorization failed: HTTP {response.status_code}"
    if response.status_code >= 400:
        return True, f"Model list returned HTTP {response.status_code}; continuing with warning."
    try:
        payload = response.json()
    except ValueError:
        return True, "Model list response is not JSON; continuing with warning."
    models = payload.get("data", payload if isinstance(payload, list) else [])
    ids = {item.get("id") for item in models if isinstance(item, dict)}
    if ids and model not in ids:
        return True, f"Configured model '{model}' was not found in model list; continuing with warning."
    return True, "API preflight passed."


def build_galtransl_config(endpoint: str, model: str, api_key: str, profile: str) -> dict[str, Any]:
    return {
        "backendSpecific": {
            "OpenAI-Compatible": {
                "tokens": [{"token": api_key, "endpoint": endpoint, "modelName": model}],
                "tokenStrategy": "fallback",
                "checkAvailable": False,
                "stream": True,
                "apiTimeout": 120,
                "apiErrorWait": "auto",
            }
        },
        "plugin": {
            "filePlugin": "file_galtransl_json",
            "textPlugins": ["text_common_normalfix"],
            "file_galtransl_json": {"output_with_src": False},
        },
        "common": {
            "gpt.numPerRequestTranslate": 16,
            "workersPerProject": 1,
            "splitFile": "no",
            "splitFileNum": 2048,
            "splitFileCrossNum": 0,
            "save_steps": 1,
            "language": "zh-cn",
            "gpt.contextNum": 8,
            "gpt.translation_guideline": profile,
            "gpt.change_prompt": "no",
            "loggingLevel": "info",
            "saveLog": True,
        },
        "proxy": {"enableProxy": False, "proxies": []},
        "problemAnalyze": {"problemList": ["词频过高", "标点错漏", "残留日文", "多加换行", "比日文长", "字典使用"]},
        "dictionary": {
            "defaultDictFolder": "Dict",
            "usePreDictInName": False,
            "usePostDictInName": False,
            "useGPTDictInName": False,
            "sortDict": True,
            "preDict": [],
            "gpt.dict": ["GPT字典.txt"],
            "postDict": [],
        },
    }


def validate_translation_output(translated: Any, ja_doc: dict[str, Any]) -> None:
    """Validate GalTransl output before converting to internal zh JSON.

    Catches malformed model output early with an actionable message instead of
    letting galtransl_to_zh silently truncate (zip) or emit empty text. Per
    ADR 0008, unparseable/misaligned translation output fails the file while
    transcription outputs are preserved.
    """
    expected = len(ja_doc.get("segments", []))
    if not isinstance(translated, list):
        raise RuntimeError(
            f"Translation output is not a JSON array (got {type(translated).__name__}); "
            f"model may have returned plain text or a wrapped object."
        )
    if not translated:
        raise RuntimeError(f"Translation output is empty; expected {expected} segments.")
    bad = [
        i for i, item in enumerate(translated)
        if not isinstance(item, dict) or "message" not in item
    ]
    if bad:
        raise RuntimeError(
            f"Translation output items at indices {bad[:5]} are missing the 'message' field."
        )
    if len(translated) < expected:
        raise RuntimeError(
            f"Translation output has {len(translated)} segments; expected {expected} "
            f"(missing {expected - len(translated)})."
        )


def translate_with_galtransl(
    root: Path,
    cache_dir: Path,
    stem: str,
    ja_doc: dict[str, Any],
    endpoint: str,
    model: str,
    api_key: str,
    profile: str,
    glossary_path: Path | None = None,
) -> dict[str, Any]:
    project_dir = cache_dir / "galtransl_project"
    input_dir = project_dir / "gt_input"
    output_dir = project_dir / "gt_output"
    dict_dir = project_dir / "Dict"
    input_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    dict_dir.mkdir(parents=True, exist_ok=True)

    # Feed the project glossary into GalTransl's GPT dictionary (TAB-separated
    # src<TAB>dst[<TAB>note]) so the model keeps names/honorlics/terms consistent.
    gpt_dict_text = ""
    if glossary_path is not None and glossary_path.exists():
        gpt_dict_text = glossary_path.read_text(encoding="utf-8")
    (dict_dir / "GPT字典.txt").write_text(gpt_dict_text, encoding="utf-8")
    write_json(input_dir / f"{stem}.json", ja_to_galtransl(ja_doc))
    # Resolve guideline to an absolute POSIX path: GalTransl's load_guideline_file
    # only prepends "translation_guidelines/" when that substring is absent, so an
    # absolute path is found regardless of the worker's cwd.
    guideline_path = root / "translation_guidelines" / profile
    if not guideline_path.exists():
        raise RuntimeError(f"Translation guideline not found: {guideline_path}")
    config = build_galtransl_config(endpoint, model, api_key, guideline_path.as_posix())
    # GalTransl resolves defaultDictFolder relative to cwd, not project_dir, so
    # point it at the project-local Dict folder with an absolute path.
    config["dictionary"]["defaultDictFolder"] = dict_dir.as_posix()
    (project_dir / "config.yaml").write_text(safe_dump(config), encoding="utf-8")

    from GalTransl.__main__ import worker

    ok = worker(str(project_dir), "config.yaml", "ForGal-json", show_banner=False)
    if not ok:
        raise RuntimeError("GalTransl worker failed")
    output_path = output_dir / f"{stem}.json"
    if not output_path.exists():
        raise RuntimeError(f"GalTransl did not produce output: {output_path}")
    try:
        translated = read_json(output_path)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"GalTransl output is not valid JSON: {exc}") from exc
    validate_translation_output(translated, ja_doc)
    return galtransl_to_zh(
        ja_doc,
        translated,
        {"backend": "galtransl", "endpoint": endpoint, "model": model, "profile": profile},
    )
