from __future__ import annotations

import json
from typing import Any

try:
    import yaml as _yaml
except Exception:  # pragma: no cover - exercised in minimal runtimes
    _yaml = None


def safe_load(text: str) -> Any:
    if _yaml is not None:
        return _yaml.safe_load(text)
    if not text.strip():
        return {}
    return json.loads(text)


def safe_dump(data: Any) -> str:
    if _yaml is not None:
        return _yaml.safe_dump(data, allow_unicode=True, sort_keys=False)
    return json.dumps(data, ensure_ascii=False, indent=2)
