from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from asmr.cache_manifest import build_stage_fingerprints
from asmr.config import load_config
from asmr.pipeline import output_paths
from asmr.storage import (
    cleanup_outputs,
    inspect_outputs,
    normalize_output_references,
    prepare_retry,
)


class StorageTests(unittest.TestCase):
    def test_safe_cleanup_removes_only_regenerable_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source, output, cache = self._create_output(Path(temp_dir))
            self._write(cache / "audio.16k.wav", 10)
            self._write(cache / "asr_chunks" / "vad_00001.wav", 20)
            self._write(cache / "galtransl_project" / "gt_output" / "scene.json", 30)
            self._write(cache / "scene.ja.json", 5)
            self._write(cache / "scene.zh.json", 6)
            self._write(cache / "quality_report.json", 7)
            self._write(output / "scene.combine.srt", 8)
            reference = self._reference(source, output)

            inspected = inspect_outputs([reference])
            self.assertEqual(inspected["summary"]["reclaimable_bytes"], 60)
            self.assertEqual(inspected["items"][0]["cache_state"], "legacy")

            cleaned = cleanup_outputs([reference], "safe_cache")

            self.assertEqual(cleaned["freed_bytes"], 60)
            self.assertTrue(source.exists())
            self.assertTrue((output / "scene.combine.srt").exists())
            self.assertTrue((cache / "scene.ja.json").exists())
            self.assertTrue((cache / "scene.zh.json").exists())
            self.assertTrue((cache / "quality_report.json").exists())
            self.assertFalse((cache / "audio.16k.wav").exists())
            self.assertFalse((cache / "asr_chunks").exists())
            self.assertFalse((cache / "galtransl_project").exists())

    def test_full_cache_and_result_deletion_never_remove_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source, output, cache = self._create_output(Path(temp_dir))
            self._write(cache / "audio.16k.wav", 10)
            self._write(cache / "scene.ja.json", 5)
            self._write(output / "scene.ja.srt", 8)
            reference = self._reference(source, output)

            cleanup_outputs([reference], "all_cache")
            self.assertTrue(source.exists())
            self.assertFalse(cache.exists())
            self.assertTrue((output / "scene.ja.srt").exists())

            deleted = cleanup_outputs([reference], "delete_result")
            self.assertEqual(deleted["deleted_count"], 1)
            self.assertTrue(source.exists())
            self.assertFalse(output.exists())

    def test_retry_invalidation_preserves_the_required_upstream_stage(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source, output, cache = self._create_output(Path(temp_dir))
            for name in ("scene.ja.json", "scene.zh.json", "quality_report.json"):
                self._write(cache / name, 5)
            self._write(cache / "audio.16k.wav", 10)
            self._write(cache / "vad_segments.json", 5)
            self._write(cache / "asr_chunks" / "vad_00001.wav", 20)
            self._write(cache / "galtransl_project" / "output.json", 20)
            for name in ("scene.ja.srt", "scene.zh.srt", "scene.combine.srt"):
                self._write(output / name, 8)
            reference = self._reference(source, output)

            prepare_retry(reference, "translation")
            self.assertTrue((cache / "scene.ja.json").exists())
            self.assertTrue((output / "scene.ja.srt").exists())
            self.assertFalse((cache / "scene.zh.json").exists())
            self.assertFalse((output / "scene.combine.srt").exists())

            self._write(cache / "scene.zh.json", 5)
            self._write(output / "scene.zh.srt", 8)
            prepare_retry(reference, "transcription")
            self.assertTrue((cache / "audio.16k.wav").exists())
            self.assertTrue((cache / "vad_segments.json").exists())
            self.assertFalse((cache / "scene.ja.json").exists())
            self.assertFalse((output / "scene.ja.srt").exists())
            self.assertTrue(source.exists())

    def test_output_reference_must_match_the_source_derived_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "scene.wav"
            source.touch()
            unrelated = root / "unrelated.voicetransl"
            unrelated.mkdir()

            with self.assertRaisesRegex(ValueError, "does not match"):
                normalize_output_references(
                    [
                        {
                            "input_path": str(source),
                            "output_dir": str(unrelated),
                        }
                    ]
                )

            self.assertTrue(unrelated.exists())

    def test_output_reference_rejects_a_file_disguised_as_an_output(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "scene.wav"
            source.touch()
            output, _cache, _stem = output_paths(source)
            output.write_text("not a directory", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "non-directory"):
                normalize_output_references(
                    [
                        {
                            "input_path": str(source),
                            "output_dir": str(output),
                        }
                    ]
                )

    def test_cache_fingerprints_invalidate_only_affected_stages(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "scene.wav"
            source.write_bytes(b"audio")
            config, _messages = load_config(root)
            self._create_fingerprint_dependencies(config)

            baseline = build_stage_fingerprints(
                config,
                source,
                transcribe_only=False,
            )
            config.settings["asr"]["intensity"] = "high"
            stronger = build_stage_fingerprints(
                config,
                source,
                transcribe_only=False,
            )
            self.assertEqual(baseline["audio"], stronger["audio"])
            self.assertEqual(baseline["vad"], stronger["vad"])
            self.assertNotEqual(baseline["asr"], stronger["asr"])
            self.assertNotEqual(baseline["translation"], stronger["translation"])

            config.settings["asr"]["intensity"] = "medium"
            config.settings["translator"]["model"] = "replacement-model"
            translated = build_stage_fingerprints(
                config,
                source,
                transcribe_only=False,
            )
            self.assertEqual(baseline["asr"], translated["asr"])
            self.assertNotEqual(baseline["translation"], translated["translation"])

    @staticmethod
    def _create_output(root: Path) -> tuple[Path, Path, Path]:
        source = root / "scene.wav"
        source.write_bytes(b"source")
        output, cache, _stem = output_paths(source)
        cache.mkdir(parents=True)
        return source, output, cache

    @staticmethod
    def _reference(source: Path, output: Path):
        return normalize_output_references(
            [{"input_path": str(source), "output_dir": str(output)}]
        )[0]

    @staticmethod
    def _write(path: Path, size: int) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"x" * size)

    @staticmethod
    def _create_fingerprint_dependencies(config) -> None:
        model_paths = config.settings["models"]
        for key in ("transwithai_whisper_ja", "whisper_base"):
            model = config.path_from_root(model_paths[key])
            model.mkdir(parents=True, exist_ok=True)
            (model / "model.bin").write_bytes(b"model")
        vad_model = config.path_from_root(model_paths["whisper_vad_onnx"])
        vad_model.parent.mkdir(parents=True, exist_ok=True)
        vad_model.write_bytes(b"vad")
        config.path_from_root(model_paths["whisper_vad_metadata"]).write_text(
            "{}",
            encoding="utf-8",
        )
        for relative in config.settings["dictionaries"].values():
            path = config.path_from_root(relative)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("", encoding="utf-8")
        guideline = (
            config.root
            / "translation_guidelines"
            / config.settings["translator"]["profile"]
        )
        guideline.parent.mkdir(parents=True, exist_ok=True)
        guideline.write_text("guide", encoding="utf-8")
