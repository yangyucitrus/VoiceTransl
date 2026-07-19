from __future__ import annotations

import json
import os
import sys
import traceback
from contextlib import redirect_stdout
from pathlib import Path
from threading import Event, Lock, Thread
from typing import Any, Callable, TextIO

from .config import load_config, public_runtime_config, update_runtime_config
from .pipeline import FileResult, PipelineCancelled, process_files
from .storage import (
    cleanup_outputs,
    inspect_outputs,
    normalize_output_references,
    prepare_retry,
)
from .vad import prepare_vad_runtime


PROTOCOL_VERSION = 1
MEDIA_EXTENSIONS = {
    ".aac",
    ".avi",
    ".flac",
    ".m4a",
    ".mkv",
    ".mov",
    ".mp3",
    ".mp4",
    ".ogg",
    ".wav",
}

ProtocolMessage = dict[str, Any]
SendMessage = Callable[[ProtocolMessage], None]
PipelineRunner = Callable[
    [Path, list[Path], dict[str, Any], Callable[[ProtocolMessage], None], Callable[[], bool]],
    list[FileResult],
]


class JsonLineWriter:
    def __init__(self, stream: TextIO) -> None:
        self._stream = stream
        self._lock = Lock()

    def __call__(self, message: ProtocolMessage) -> None:
        encoded = json.dumps(message, ensure_ascii=False, separators=(",", ":"))
        with self._lock:
            self._stream.write(encoded + "\n")
            self._stream.flush()


def run_pipeline(
    root: Path,
    inputs: list[Path],
    options: dict[str, Any],
    on_event: Callable[[ProtocolMessage], None],
    should_cancel: Callable[[], bool],
) -> list[FileResult]:
    settings_path = options.get("settings_path")
    config, messages = load_config(root, Path(settings_path) if settings_path else None)
    for message in messages:
        on_event({"type": "config_message", "message": message})
    return process_files(
        config,
        inputs,
        transcribe_only=options["transcribe_only"],
        no_cache=not options["reuse_cache"],
        skip_api_preflight=options["skip_api_preflight"],
        limit_segments=options["limit_segments"],
        start_segment=options["start_segment"],
        on_event=on_event,
        should_cancel=should_cancel,
    )


class WorkerServer:
    def __init__(
        self,
        root: Path,
        send: SendMessage,
        runner: PipelineRunner = run_pipeline,
    ) -> None:
        self.root = root.resolve()
        self._send = send
        self._runner = runner
        self._state_lock = Lock()
        self._thread: Thread | None = None
        self._cancel_event: Event | None = None
        self._active_request_id: str | None = None

    @property
    def running(self) -> bool:
        with self._state_lock:
            return self._thread is not None and self._thread.is_alive()

    def send_ready(self) -> None:
        self._send(
            {
                "type": "ready",
                "protocol": PROTOCOL_VERSION,
                "pid": os.getpid(),
                "root": str(self.root),
            }
        )

    def handle_message(self, message: ProtocolMessage) -> bool:
        command = str(message.get("command", "")).strip().lower()
        request_id = str(message.get("request_id", "")).strip() or None
        if command == "ping":
            self._send(
                {
                    "type": "pong",
                    "request_id": request_id,
                    "protocol": PROTOCOL_VERSION,
                }
            )
            return True
        if command == "get_config":
            if request_id is None:
                self._reject(None, "get_config requires request_id")
                return True
            try:
                config, _messages = load_config(self.root)
                payload = public_runtime_config(config)
            except Exception as exc:
                self._reject(request_id, str(exc))
            else:
                self._send(
                    {
                        "type": "config",
                        "request_id": request_id,
                        "config": payload,
                    }
                )
            return True
        if command == "save_config":
            if request_id is None:
                self._reject(None, "save_config requires request_id")
                return True
            with self._state_lock:
                busy = self._thread is not None and self._thread.is_alive()
            if busy:
                self._reject(request_id, "Configuration cannot change while a task is running")
                return True
            raw_config = message.get("config")
            if not isinstance(raw_config, dict):
                self._reject(request_id, "save_config requires a config object")
                return True
            try:
                payload = update_runtime_config(self.root, raw_config)
            except (OSError, TypeError, ValueError) as exc:
                self._reject(request_id, str(exc))
            else:
                self._send(
                    {
                        "type": "config_saved",
                        "request_id": request_id,
                        "config": payload,
                    }
                )
            return True
        if command == "inspect_storage":
            if request_id is None:
                self._reject(None, "inspect_storage requires request_id")
                return True
            if self.running:
                self._reject(
                    request_id,
                    "Storage cannot be inspected while a task is running",
                )
                return True
            try:
                references = normalize_output_references(message.get("items"))
                payload = inspect_outputs(references)
            except (OSError, TypeError, ValueError) as exc:
                self._reject(request_id, str(exc))
            else:
                self._send(
                    {
                        "type": "storage",
                        "request_id": request_id,
                        **payload,
                    }
                )
            return True
        if command == "cleanup_outputs":
            if request_id is None:
                self._reject(None, "cleanup_outputs requires request_id")
                return True
            if self.running:
                self._reject(
                    request_id,
                    "Outputs cannot be cleaned while a task is running",
                )
                return True
            try:
                references = normalize_output_references(message.get("items"))
                payload = cleanup_outputs(
                    references,
                    str(message.get("mode", "")),
                )
            except (OSError, TypeError, ValueError) as exc:
                self._reject(request_id, str(exc))
            else:
                self._send(
                    {
                        "type": "outputs_cleaned",
                        "request_id": request_id,
                        **payload,
                    }
                )
            return True
        if command == "prepare_retry":
            if request_id is None:
                self._reject(None, "prepare_retry requires request_id")
                return True
            if self.running:
                self._reject(
                    request_id,
                    "A retry cannot be prepared while a task is running",
                )
                return True
            try:
                references = normalize_output_references(message.get("items"))
                if len(references) != 1:
                    raise ValueError("prepare_retry requires exactly one output item")
                payload = prepare_retry(
                    references[0],
                    str(message.get("stage", "")),
                )
            except (OSError, TypeError, ValueError) as exc:
                self._reject(request_id, str(exc))
            else:
                self._send(
                    {
                        "type": "retry_prepared",
                        "request_id": request_id,
                        **payload,
                    }
                )
            return True
        if command == "run":
            self._start_request(message, request_id)
            return True
        if command == "cancel":
            self._cancel_request(request_id)
            return True
        if command == "shutdown":
            self._cancel_request(request_id, quiet_when_idle=True)
            self._send({"type": "shutdown_ack", "request_id": request_id})
            return False
        self._reject(request_id, f"Unknown command: {command or '<empty>'}")
        return True

    def wait_for_idle(self, timeout: float | None = None) -> bool:
        with self._state_lock:
            thread = self._thread
        if thread is None:
            return True
        thread.join(timeout)
        return not thread.is_alive()

    def _start_request(self, message: ProtocolMessage, request_id: str | None) -> None:
        if request_id is None:
            self._reject(None, "run requires request_id")
            return
        try:
            inputs = self._normalize_inputs(message.get("inputs"))
            options = self._normalize_options(message.get("options"))
        except (TypeError, ValueError) as exc:
            self._reject(request_id, str(exc))
            return

        with self._state_lock:
            if self._thread is not None and self._thread.is_alive():
                self._reject(request_id, "A pipeline request is already running")
                return
            cancel_event = Event()
            thread = Thread(
                target=self._run_request,
                args=(request_id, inputs, options, cancel_event),
                name="voicetransl-pipeline",
                daemon=True,
            )
            self._cancel_event = cancel_event
            self._active_request_id = request_id
            self._thread = thread

        self._send(
            {
                "type": "accepted",
                "request_id": request_id,
                "file_count": len(inputs),
            }
        )
        thread.start()

    def _run_request(
        self,
        request_id: str,
        inputs: list[Path],
        options: dict[str, Any],
        cancel_event: Event,
    ) -> None:
        def forward_event(event: ProtocolMessage) -> None:
            self._send(
                {
                    "type": "event",
                    "request_id": request_id,
                    "event": event,
                }
            )

        try:
            # stdout is reserved for JSONL protocol messages.
            with redirect_stdout(sys.stderr):
                results = self._runner(
                    self.root,
                    inputs,
                    options,
                    forward_event,
                    cancel_event.is_set,
                )
            payload = [self._result_payload(result) for result in results]
            self._send(
                {
                    "type": "completed",
                    "request_id": request_id,
                    "cancelled": cancel_event.is_set()
                    or any(item["status"] == "cancelled" for item in payload),
                    "results": payload,
                }
            )
        except PipelineCancelled:
            self._send(
                {
                    "type": "completed",
                    "request_id": request_id,
                    "cancelled": True,
                    "results": [],
                }
            )
        except Exception as exc:
            traceback.print_exc(file=sys.stderr)
            self._send(
                {
                    "type": "error",
                    "request_id": request_id,
                    "message": str(exc),
                }
            )
        finally:
            with self._state_lock:
                if self._active_request_id == request_id:
                    self._thread = None
                    self._cancel_event = None
                    self._active_request_id = None

    def _cancel_request(
        self,
        request_id: str | None,
        *,
        quiet_when_idle: bool = False,
    ) -> None:
        with self._state_lock:
            cancel_event = self._cancel_event
            active_request_id = self._active_request_id
        if cancel_event is None or active_request_id is None:
            if not quiet_when_idle:
                self._reject(request_id, "No pipeline request is running")
            return
        if request_id is not None and request_id != active_request_id:
            self._reject(request_id, "request_id does not match the active request")
            return
        cancel_event.set()
        self._send(
            {
                "type": "cancel_requested",
                "request_id": active_request_id,
            }
        )

    def _normalize_inputs(self, raw_inputs: Any) -> list[Path]:
        if not isinstance(raw_inputs, list) or not raw_inputs:
            raise ValueError("run requires a non-empty inputs list")
        inputs: list[Path] = []
        seen: set[str] = set()
        for raw_path in raw_inputs:
            if not isinstance(raw_path, str) or not raw_path.strip():
                raise ValueError("Every input must be a non-empty path string")
            path = Path(raw_path).expanduser().resolve()
            if not path.is_file():
                raise ValueError(f"Input file does not exist: {path}")
            if path.suffix.lower() not in MEDIA_EXTENSIONS:
                raise ValueError(f"Unsupported media type: {path.suffix or '<none>'}")
            key = str(path).casefold()
            if key not in seen:
                seen.add(key)
                inputs.append(path)
        return inputs

    @staticmethod
    def _normalize_options(raw_options: Any) -> dict[str, Any]:
        if raw_options is None:
            raw_options = {}
        if not isinstance(raw_options, dict):
            raise TypeError("options must be a JSON object")
        limit_segments = raw_options.get("limit_segments")
        start_segment = raw_options.get("start_segment", 0)
        if limit_segments is not None and (
            isinstance(limit_segments, bool)
            or not isinstance(limit_segments, int)
            or limit_segments <= 0
        ):
            raise ValueError("limit_segments must be a positive integer or null")
        if isinstance(start_segment, bool) or not isinstance(start_segment, int) or start_segment < 0:
            raise ValueError("start_segment must be a non-negative integer")
        settings_path = raw_options.get("settings_path")
        if settings_path is not None and not isinstance(settings_path, str):
            raise ValueError("settings_path must be a path string or null")
        transcribe_only = bool(raw_options.get("transcribe_only", True))
        return {
            "transcribe_only": transcribe_only,
            "reuse_cache": bool(raw_options.get("reuse_cache", True)),
            "skip_api_preflight": bool(
                raw_options.get("skip_api_preflight", transcribe_only)
            ),
            "limit_segments": limit_segments,
            "start_segment": start_segment,
            "settings_path": settings_path,
        }

    @staticmethod
    def _result_payload(result: FileResult) -> ProtocolMessage:
        return {
            "input_path": str(result.input_path),
            "name": result.input_path.name,
            "status": result.status,
            "output_dir": str(result.output_dir),
            "warnings": result.warnings,
            "error": result.error,
        }

    def _reject(self, request_id: str | None, message: str) -> None:
        self._send(
            {
                "type": "rejected",
                "request_id": request_id,
                "message": message,
            }
        )


def serve_stdio(root: Path | None = None) -> int:
    for stream in (sys.stdin, sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

    writer = JsonLineWriter(sys.stdout)
    writer({"type": "log", "message": "正在初始化本地 VAD 运行时"})
    try:
        prepare_vad_runtime()
    except Exception as exc:
        traceback.print_exc(file=sys.stderr)
        writer({"type": "error", "message": f"VAD runtime initialization failed: {exc}"})
        return 1
    server = WorkerServer(root or Path(__file__).resolve().parents[1], writer)
    server.send_ready()
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
            if not isinstance(message, dict):
                raise ValueError("Protocol message must be a JSON object")
        except (json.JSONDecodeError, ValueError) as exc:
            writer({"type": "protocol_error", "message": str(exc)})
            continue
        if not server.handle_message(message):
            break
    server._cancel_request(None, quiet_when_idle=True)
    server.wait_for_idle(5.0)
    return 0
