from __future__ import annotations

import json
import sys
import tempfile
import unittest
from io import StringIO
from pathlib import Path
from threading import Event, Lock, current_thread
from time import sleep
from unittest.mock import patch

from asmr.config import load_config
from asmr.pipeline import FileResult
from asmr.transcribe import resolve_beam_size
from asmr.worker_protocol import WorkerServer, serve_stdio


class MessageCollector:
    def __init__(self) -> None:
        self.messages: list[dict] = []
        self.lock = Lock()

    def __call__(self, message: dict) -> None:
        with self.lock:
            self.messages.append(message)

    def types(self) -> list[str]:
        with self.lock:
            return [str(message["type"]) for message in self.messages]


class WorkerProtocolTests(unittest.TestCase):
    def test_serve_stdio_prepares_vad_runtime_on_main_thread_before_ready(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            order: list[tuple[str, object]] = []
            stdin = StringIO('{"command":"shutdown"}\n')
            stdout = StringIO()
            stderr = StringIO()
            original_send_ready = WorkerServer.send_ready

            def prepare_runtime() -> None:
                order.append(("prepare", current_thread()))

            def send_ready(server: WorkerServer) -> None:
                order.append(("ready", current_thread()))
                original_send_ready(server)

            with (
                patch("asmr.worker_protocol.prepare_vad_runtime", prepare_runtime),
                patch.object(WorkerServer, "send_ready", send_ready),
                patch.object(sys, "stdin", stdin),
                patch.object(sys, "stdout", stdout),
                patch.object(sys, "stderr", stderr),
            ):
                self.assertEqual(serve_stdio(Path(temp_dir)), 0)

            self.assertEqual([item[0] for item in order], ["prepare", "ready"])
            self.assertTrue(all(item[1] is current_thread() for item in order))
            messages = [json.loads(line) for line in stdout.getvalue().splitlines()]
            self.assertEqual(
                [message["type"] for message in messages],
                ["log", "ready", "shutdown_ack"],
            )

    def test_run_forwards_events_and_serializes_results(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            audio = root / "scene.wav"
            audio.touch()
            collector = MessageCollector()

            def fake_runner(_root, inputs, options, on_event, should_cancel):
                self.assertEqual(inputs, [audio.resolve()])
                self.assertTrue(options["transcribe_only"])
                self.assertFalse(should_cancel())
                on_event(
                    {
                        "type": "stage_started",
                        "stage": "asr",
                        "stage_index": 3,
                        "stage_count": 5,
                    }
                )
                return [FileResult(inputs[0], "transcribe_only", root / "out")]

            server = WorkerServer(root, collector, runner=fake_runner)
            server.handle_message(
                {
                    "command": "run",
                    "request_id": "run-1",
                    "inputs": [str(audio)],
                    "options": {"transcribe_only": True},
                }
            )

            self.assertTrue(server.wait_for_idle(2.0))
            self.assertEqual(
                collector.types(),
                ["accepted", "event", "completed"],
            )
            completed = collector.messages[-1]
            self.assertFalse(completed["cancelled"])
            self.assertEqual(completed["results"][0]["status"], "transcribe_only")

    def test_cancel_sets_the_pipeline_cancel_check(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            audio = root / "scene.flac"
            audio.touch()
            collector = MessageCollector()
            started = Event()

            def cancellable_runner(_root, inputs, _options, _on_event, should_cancel):
                started.set()
                while not should_cancel():
                    sleep(0.005)
                return [FileResult(inputs[0], "cancelled", root / "out")]

            server = WorkerServer(root, collector, runner=cancellable_runner)
            server.handle_message(
                {
                    "command": "run",
                    "request_id": "run-2",
                    "inputs": [str(audio)],
                }
            )
            self.assertTrue(started.wait(1.0))
            server.handle_message({"command": "cancel", "request_id": "run-2"})

            self.assertTrue(server.wait_for_idle(2.0))
            self.assertEqual(
                collector.types(),
                ["accepted", "cancel_requested", "completed"],
            )
            self.assertTrue(collector.messages[-1]["cancelled"])

    def test_invalid_input_is_rejected_without_starting_a_thread(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            collector = MessageCollector()
            server = WorkerServer(Path(temp_dir), collector)

            server.handle_message(
                {
                    "command": "run",
                    "request_id": "run-3",
                    "inputs": [str(Path(temp_dir) / "missing.wav")],
                }
            )

            self.assertFalse(server.running)
            self.assertEqual(collector.types(), ["rejected"])
            self.assertIn("does not exist", collector.messages[0]["message"])

    def test_ping_reports_protocol_version(self) -> None:
        collector = MessageCollector()
        server = WorkerServer(Path.cwd(), collector)

        server.handle_message({"command": "ping", "request_id": "ping-1"})

        self.assertEqual(collector.messages[0]["type"], "pong")
        self.assertEqual(collector.messages[0]["protocol"], 1)

    def test_reads_and_saves_runtime_configuration_without_echoing_secret(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            collector = MessageCollector()
            server = WorkerServer(root, collector)

            server.handle_message({"command": "get_config", "request_id": "config-1"})
            initial = collector.messages[-1]
            self.assertEqual(initial["type"], "config")
            self.assertEqual(initial["config"]["transcription_intensity"], "medium")
            self.assertFalse(initial["config"]["api_key_configured"])

            server.handle_message(
                {
                    "command": "save_config",
                    "request_id": "config-2",
                    "config": {
                        "transcription_intensity": "high",
                        "translation_endpoint": "http://127.0.0.1:8000/v1/chat/completions",
                        "translation_model": "local-model",
                        "api_key": "test-secret-key",
                    },
                }
            )

            saved = collector.messages[-1]
            self.assertEqual(saved["type"], "config_saved")
            self.assertEqual(saved["config"]["transcription_intensity"], "high")
            self.assertEqual(
                saved["config"]["translation_endpoint"],
                "http://127.0.0.1:8000",
            )
            self.assertEqual(saved["config"]["translation_model"], "local-model")
            self.assertTrue(saved["config"]["api_key_configured"])
            self.assertNotIn("test-secret-key", repr(collector.messages))

            config, _messages = load_config(root)
            self.assertEqual(config.settings["asr"]["intensity"], "high")
            self.assertEqual(config.api_key, "test-secret-key")

            server.handle_message(
                {
                    "command": "save_config",
                    "request_id": "config-2b",
                    "config": {"translation_model": "replacement-model"},
                }
            )
            preserved, _messages = load_config(root)
            self.assertEqual(preserved.settings["translator"]["model"], "replacement-model")
            self.assertEqual(preserved.api_key, "test-secret-key")

    def test_rejects_invalid_runtime_configuration(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            collector = MessageCollector()
            server = WorkerServer(Path(temp_dir), collector)

            server.handle_message(
                {
                    "command": "save_config",
                    "request_id": "config-3",
                    "config": {"translation_endpoint": "localhost:8000"},
                }
            )

            self.assertEqual(collector.messages[-1]["type"], "rejected")
            self.assertIn("http://", collector.messages[-1]["message"])

    def test_transcription_intensity_controls_beam_search(self) -> None:
        self.assertEqual(resolve_beam_size("low"), 1)
        self.assertEqual(resolve_beam_size("medium"), 5)
        self.assertEqual(resolve_beam_size("high"), 8)
        self.assertEqual(resolve_beam_size("unknown"), 5)

    def test_storage_commands_inspect_and_clean_validated_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "scene.wav"
            source.write_bytes(b"source")
            output = root / "scene.voicetransl"
            cache = output / "cache"
            cache.mkdir(parents=True)
            (cache / "audio.16k.wav").write_bytes(b"cached-audio")
            (output / "scene.ja.srt").write_text("subtitle", encoding="utf-8")
            collector = MessageCollector()
            server = WorkerServer(root, collector)
            items = [{"input_path": str(source), "output_dir": str(output)}]

            server.handle_message(
                {
                    "command": "inspect_storage",
                    "request_id": "storage-1",
                    "items": items,
                }
            )
            self.assertEqual(collector.messages[-1]["type"], "storage")
            self.assertEqual(
                collector.messages[-1]["summary"]["reclaimable_bytes"],
                len(b"cached-audio"),
            )

            server.handle_message(
                {
                    "command": "cleanup_outputs",
                    "request_id": "storage-2",
                    "items": items,
                    "mode": "safe_cache",
                }
            )
            self.assertEqual(collector.messages[-1]["type"], "outputs_cleaned")
            self.assertFalse((cache / "audio.16k.wav").exists())
            self.assertTrue(source.exists())
            self.assertTrue((output / "scene.ja.srt").exists())

            (cache / "scene.ja.json").write_text("{}", encoding="utf-8")
            (cache / "scene.zh.json").write_text("{}", encoding="utf-8")
            server.handle_message(
                {
                    "command": "prepare_retry",
                    "request_id": "retry-1",
                    "items": items,
                    "stage": "translation",
                }
            )
            self.assertEqual(collector.messages[-1]["type"], "retry_prepared")
            self.assertTrue((cache / "scene.ja.json").exists())
            self.assertFalse((cache / "scene.zh.json").exists())


if __name__ == "__main__":
    unittest.main()
