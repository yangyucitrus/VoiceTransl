"""VoiceTransl ASMR GUI — minimal task tab (Flet / Material 3)."""
from __future__ import annotations

import os
import subprocess
import sys
import threading
from pathlib import Path

import flet as ft

from asmr.config import load_config
from asmr.models import check_model_readiness
from asmr.pipeline import process_files

ROOT = Path(__file__).resolve().parent
AUDIO_EXTS = ["mp3", "wav", "flac", "m4a", "aac", "ogg", "mp4", "mkv", "mov", "avi"]


class GuiStream:
    """Redirect stdout/stderr lines to a callback (called from worker thread)."""

    def __init__(self, on_line):
        self._on_line = on_line
        self._buf = ""

    def write(self, text):
        if not text:
            return 0
        self._buf += text
        while "\n" in self._buf:
            line, self._buf = self._buf.split("\n", 1)
            self._on_line(line)
        return len(text)

    def flush(self):
        if self._buf:
            self._on_line(self._buf)
            self._buf = ""


def main(page: ft.Page):
    page.title = "VoiceTransl ASMR"
    page.theme_mode = ft.ThemeMode.SYSTEM
    page.window.width = 1000
    page.window.height = 740
    page.padding = 24

    config, _ = load_config(ROOT)
    state = {"files": [], "running": False}

    # --- controls ---
    file_list = ft.ListView(height=140, spacing=2)
    log_view = ft.ListView(expand=True, spacing=0, auto_scroll=True)
    progress = ft.ProgressBar(width=560, visible=False)
    status = ft.Text("就绪", size=14)
    done_list = ft.Column(spacing=4, scroll=ft.ScrollMode.AUTO, height=110)

    device_dd = ft.Dropdown(
        label="设备",
        value=config.settings["asr"]["device_preset"],
        options=[ft.dropdown.Option(d) for d in ["cpu", "gpu_quality", "gpu_low_vram"]],
        width=200,
    )
    to_switch = ft.Switch(
        label="仅转录(跳过翻译)",
        value=bool(config.settings["pipeline"].get("transcribe_only")),
    )
    limit_field = ft.TextField(
        label="限制段数(调试)",
        width=170,
        keyboard_type=ft.KeyboardType.NUMBER,
    )

    start_btn = ft.FilledButton("开始", icon=ft.Icons.PLAY_ARROW)
    check_btn = ft.ElevatedButton("检查模型", icon=ft.Icons.CHECK_CIRCLE)
    open_btn = ft.OutlinedButton("打开输出目录", icon=ft.Icons.FOLDER_OPEN, disabled=True)

    file_picker = ft.FilePicker()
    page.services.append(file_picker)

    def log(line: str):
        log_view.controls.append(ft.Text(line, size=12, selectable=True))
        if len(log_view.controls) > 500:
            log_view.controls = log_view.controls[-500:]
        page.update()

    def set_running(running: bool):
        state["running"] = running
        start_btn.disabled = running
        start_btn.text = "运行中..." if running else "开始"
        device_dd.disabled = running
        to_switch.disabled = running
        limit_field.disabled = running
        progress.visible = running
        page.update()

    async def pick_files(_):
        files = await file_picker.pick_files(allow_multiple=True, allowed_extensions=AUDIO_EXTS)
        if not files:
            return
        state["files"] = [Path(f.path) for f in files]
        file_list.controls.clear()
        for f in state["files"]:
            file_list.controls.append(ft.Text(f"• {f.name}", size=13))
        status.value = f"已选 {len(state['files'])} 个文件"
        page.update()

    add_btn = ft.ElevatedButton("添加文件", icon=ft.Icons.FILE_OPEN, on_click=pick_files)

    def run_pipeline():
        config.settings["asr"]["device_preset"] = device_dd.value
        config.settings["pipeline"]["transcribe_only"] = to_switch.value
        limit = None
        if limit_field.value and limit_field.value.strip():
            try:
                limit = int(limit_field.value.strip())
            except ValueError:
                log(f"[warn] 无效的段数限制: {limit_field.value}")
        stream = GuiStream(log)
        old_out, old_err = sys.stdout, sys.stderr
        sys.stdout = stream
        sys.stderr = stream
        try:
            results = process_files(
                config,
                state["files"],
                transcribe_only=to_switch.value,
                no_cache=False,
                skip_api_preflight=False,
                limit_segments=limit,
                start_segment=0,
            )
            done_list.controls.clear()
            for r in results:
                if r.status in ("success", "transcribe_only"):
                    color = ft.Colors.GREEN
                elif r.status == "failed":
                    color = ft.Colors.RED
                else:
                    color = ft.Colors.ORANGE
                suffix = f"  warnings={r.warnings}" if r.warnings else ""
                if r.error:
                    suffix += f"  error={r.error[:80]}"
                done_list.controls.append(
                    ft.Text(f"[{r.status}] {r.input_path.name}{suffix}", color=color, size=12)
                )
            log(f"=== 完成: {len(results)} 个文件 ===")
            open_btn.disabled = False
        except Exception as exc:
            log(f"[error] {exc}")
        finally:
            sys.stdout = old_out
            sys.stderr = old_err
            set_running(False)

    def on_start(_):
        if not state["files"]:
            log("请先添加文件")
            return
        set_running(True)
        done_list.controls.clear()
        log_view.controls.clear()
        log(f"开始处理 {len(state['files'])} 个文件 (device={device_dd.value}, transcribe_only={to_switch.value})")
        threading.Thread(target=run_pipeline, daemon=True).start()

    start_btn.on_click = on_start

    def on_check(_):
        missing = check_model_readiness(config, transcribe_only=to_switch.value)
        if missing:
            for m in missing:
                log(f"[missing] {m}")
        else:
            log("[ok] 所有模型路径存在")

    check_btn.on_click = on_check

    def on_open(_):
        if not state["files"]:
            return
        out_dir = state["files"][0].with_suffix("").with_name(state["files"][0].stem + ".voicetransl")
        if not out_dir.exists():
            log(f"输出目录不存在: {out_dir}")
            return
        if sys.platform == "win32":
            os.startfile(str(out_dir))
        else:
            subprocess.Popen(["xdg-open", str(out_dir)])

    open_btn.on_click = on_open

    # --- layout ---
    page.add(
        ft.Row(
            [ft.Icon(ft.Icons.GRAPHIC_EQ, size=32), ft.Text("VoiceTransl ASMR", size=26, weight=ft.FontWeight.BOLD)],
            alignment=ft.MainAxisAlignment.START,
        ),
        ft.Card(
            ft.Container(
                ft.Column(
                    [
                        ft.Row([add_btn, check_btn]),
                        ft.Container(file_list, padding=ft.Padding(left=8, top=0, right=0, bottom=0)),
                        ft.Row([device_dd, to_switch, limit_field]),
                        ft.Row([start_btn, open_btn]),
                        progress,
                        status,
                    ],
                    spacing=12,
                ),
                padding=16,
            )
        ),
        ft.Text("结果", size=16, weight=ft.FontWeight.BOLD),
        done_list,
        ft.Text("日志", size=16, weight=ft.FontWeight.BOLD),
        log_view,
    )


if __name__ == "__main__":
    ft.app(target=main)
