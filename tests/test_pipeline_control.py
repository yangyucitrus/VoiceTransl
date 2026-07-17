from __future__ import annotations

import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from asmr.pipeline import FileResult, PipelineCancelled, process_files, process_one


class PipelineControlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = SimpleNamespace(
            settings={
                "pipeline": {
                    "preflight_translation_api": False,
                    "continue_on_error": True,
                }
            }
        )

    @patch("asmr.pipeline.check_model_readiness", return_value=[])
    @patch("asmr.pipeline.require_config_ready")
    def test_events_include_file_context_and_cancel_between_files(
        self,
        _require_config_ready,
        _check_model_readiness,
    ) -> None:
        inputs = [Path("one.wav"), Path("two.wav")]
        events: list[dict] = []
        cancel_requested = False

        def fake_process_one(
            _config,
            input_path,
            _transcribe_only,
            _no_cache,
            _limit_segments,
            _start_segment,
            *,
            on_event,
            should_cancel,
        ) -> FileResult:
            nonlocal cancel_requested
            self.assertFalse(should_cancel())
            on_event(
                {
                    "type": "stage_started",
                    "stage": "audio",
                    "stage_index": 1,
                    "stage_count": 5,
                }
            )
            cancel_requested = True
            return FileResult(input_path, "success", Path("output"))

        with patch("asmr.pipeline.process_one", side_effect=fake_process_one) as mocked:
            results = process_files(
                self.config,
                inputs,
                transcribe_only=True,
                no_cache=False,
                skip_api_preflight=True,
                on_event=events.append,
                should_cancel=lambda: cancel_requested,
            )

        self.assertEqual(mocked.call_count, 1)
        self.assertEqual([result.status for result in results], ["success"])
        self.assertEqual(
            [event["type"] for event in events],
            [
                "batch_started",
                "file_started",
                "stage_started",
                "file_finished",
                "batch_finished",
            ],
        )
        stage_event = events[2]
        self.assertEqual(stage_event["file_index"], 0)
        self.assertEqual(stage_event["name"], "one.wav")
        self.assertTrue(events[-1]["cancelled"])

    @patch("asmr.pipeline.check_model_readiness", return_value=[])
    @patch("asmr.pipeline.require_config_ready")
    def test_cancel_during_file_returns_cancelled_result(
        self,
        _require_config_ready,
        _check_model_readiness,
    ) -> None:
        events: list[dict] = []

        with patch("asmr.pipeline.process_one", side_effect=PipelineCancelled()):
            results = process_files(
                self.config,
                [Path("one.wav")],
                transcribe_only=True,
                no_cache=False,
                skip_api_preflight=True,
                on_event=events.append,
            )

        self.assertEqual(len(results), 1)
        self.assertEqual(results[0].status, "cancelled")
        self.assertEqual(events[-2]["type"], "file_finished")
        self.assertEqual(events[-2]["status"], "cancelled")
        self.assertTrue(events[-1]["cancelled"])

    def test_process_one_rejects_an_engine_the_pipeline_does_not_support(self) -> None:
        config = SimpleNamespace(settings={"asr": {"engine": "sherpa_ja"}})

        with self.assertRaisesRegex(RuntimeError, "Unsupported ASR engine"):
            process_one(config, Path("one.wav"), True, False)


if __name__ == "__main__":
    unittest.main()
