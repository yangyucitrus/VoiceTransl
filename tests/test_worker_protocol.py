from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from threading import Event, Lock
from time import sleep

from asmr.pipeline import FileResult
from asmr.worker_protocol import WorkerServer


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


if __name__ == "__main__":
    unittest.main()
