from __future__ import annotations

from pathlib import Path


def load_replacements(path: Path) -> list[tuple[str, str]]:
    if not path.exists():
        return []
    pairs: list[tuple[str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=>" in line:
            src, dst = line.split("=>", 1)
        elif "\t" in line:
            src, dst = line.split("\t", 1)
        else:
            continue
        pairs.append((src.strip(), dst.strip()))
    return pairs


def apply_replacements(text: str, pairs: list[tuple[str, str]]) -> str:
    for src, dst in pairs:
        text = text.replace(src, dst)
    return text
