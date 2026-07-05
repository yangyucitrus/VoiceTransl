"""VoiceTransl ASMR GUI — Flet / Material 3 (棉花糖配色 + MD3 tokens + 米哈游式分组卡)."""
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
from asmr.translate import preflight_api

ROOT = Path(__file__).resolve().parent
AUDIO_EXTS = ["mp3", "wav", "flac", "m4a", "aac", "ogg", "mp4", "mkv", "mov", "avi"]
VAD_PRESETS = ["standard_asmr", "whisper_sensitive", "clean_conservative"]
DEVICE_PRESETS = ["cpu", "gpu_quality", "gpu_low_vram"]
PROFILE_FILES = sorted(p.name for p in (ROOT / "translation_guidelines").glob("*.md"))

# === design tokens (棉花糖配色 + MD3 间距/字号/圆角系统) ===
C_BG = "#FFFBF5"          # Cream 底
C_CARD = "#FFF0F5"        # Marshmallow 卡面
C_PRIMARY = "#FF8FB1"     # Sakura 粉（主强调）
C_SECONDARY = "#7ED4A8"   # Mint 薄荷（次强调 / OK）
C_TEXT = "#4A3B55"        # 深可可（正文，比浅可可更深以保证对比度）
C_SUB = "#8A7A9A"        # 副文本（淡紫棕）

R_CARD = 16               # MD3 Large
R_BOX = 12                # 容器/日志框
S_SEC = 24                 # 区块间 (MD3 section)
S_CARD = 18               # 卡内 padding
S_ITEM = 10               # 卡内控件间
SZ_TITLE = 28             # Headline Medium
SZ_SUB = 13               # Title Small（副标题）
SZ_SECTION = 16           # Title Medium（区块标题）
SZ_BODY = 13              # Body Small


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
    page.theme_mode = ft.ThemeMode.LIGHT
    page.theme = ft.Theme(color_scheme_seed=ft.Colors.PINK, font_family="幼圆")
    page.bgcolor = C_BG
    page.window.width = 1160
    page.window.height = 780
    page.padding = 0

    config, _ = load_config(ROOT)
    state = {"files": [], "running": False, "last_results": []}

    _Card = ft.Card

    def card(content):
        return _Card(
            content,
            shape=ft.RoundedRectangleBorder(radius=R_CARD),
            elevation=1,
            shadow_color=C_PRIMARY,
            bgcolor=C_CARD,
        )

    def section(title, subtitle="", icon=None):
        head = []
        if icon:
            head.append(ft.Icon(icon, color=C_PRIMARY, size=28))
        head.append(ft.Text(title, size=SZ_TITLE, weight=ft.FontWeight.BOLD, color=C_PRIMARY))
        children = [ft.Row(head, spacing=8)]
        if subtitle:
            children.append(ft.Text(subtitle, size=SZ_SUB, color=C_SUB))
        return ft.Column(children, spacing=2)

    def field_label(text):
        return ft.Text(text, size=SZ_SECTION, weight=ft.FontWeight.BOLD, color=C_TEXT)

    # --- shared controls ---
    file_list = ft.ListView(height=130, spacing=2)
    log_view = ft.ListView(expand=True, spacing=0, auto_scroll=True)
    progress = ft.ProgressBar(width=520, visible=False, color=C_PRIMARY)
    status = ft.Text("就绪", size=14, color=C_SUB)
    done_list = ft.Column(spacing=4, scroll=ft.ScrollMode.AUTO, height=100)

    device_dd = ft.Dropdown(
        label="设备 preset",
        value=config.settings["asr"]["device_preset"],
        options=[ft.dropdown.Option(d) for d in DEVICE_PRESETS],
        width=260,
    )
    vad_dd = ft.Dropdown(
        label="VAD preset",
        value=config.settings["vad"]["preset"],
        options=[ft.dropdown.Option(v) for v in VAD_PRESETS],
        width=260,
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

    endpoint_field = ft.TextField(
        label="endpoint",
        value=config.settings["translator"]["endpoint"],
        width=420,
    )
    model_field = ft.TextField(
        label="model",
        value=config.settings["translator"]["model"],
        width=300,
    )
    profile_dd = ft.Dropdown(
        label="profile",
        value=config.settings["translator"]["profile"],
        options=[ft.dropdown.Option(p) for p in PROFILE_FILES],
        width=300,
    )
    api_key_field = ft.TextField(
        label="API key (VOICETRANSL_API_KEY)",
        value=config.api_key or "",
        password=True,
        can_reveal_password=True,
        width=420,
    )
    test_result = ft.Text("", size=13)

    start_btn = ft.FilledButton("开始", icon=ft.Icons.PLAY_ARROW)
    open_btn = ft.OutlinedButton("打开输出目录", icon=ft.Icons.FOLDER_OPEN, disabled=True)
    file_picker = ft.FilePicker()
    page.services.append(file_picker)

    def log(line: str):
        log_view.controls.append(ft.Text(line, size=SZ_BODY, selectable=True, color=C_TEXT))
        if len(log_view.controls) > 500:
            log_view.controls = log_view.controls[-500:]
        page.update()

    def set_running(running: bool):
        state["running"] = running
        start_btn.disabled = running
        start_btn.text = "运行中..." if running else "开始"
        for c in [to_switch, limit_field, device_dd, vad_dd, endpoint_field, model_field, profile_dd, api_key_field]:
            c.disabled = running
        progress.visible = running
        page.update()

    async def pick_files(_):
        files = await file_picker.pick_files(allow_multiple=True, allowed_extensions=AUDIO_EXTS)
        if not files:
            return
        state["files"] = [Path(f.path) for f in files]
        file_list.controls.clear()
        for f in state["files"]:
            file_list.controls.append(ft.Text(f"- {f.name}", size=SZ_BODY, color=C_TEXT))
        status.value = f"已选 {len(state['files'])} 个文件"
        page.update()

    add_btn = ft.ElevatedButton("添加文件", icon=ft.Icons.FILE_OPEN, on_click=pick_files)

    def apply_config():
        config.settings["asr"]["device_preset"] = device_dd.value
        config.settings["vad"]["preset"] = vad_dd.value
        config.settings["pipeline"]["transcribe_only"] = to_switch.value
        config.settings["translator"]["endpoint"] = endpoint_field.value
        config.settings["translator"]["model"] = model_field.value
        config.settings["translator"]["profile"] = profile_dd.value
        config.api_key = api_key_field.value or None

    def run_pipeline():
        apply_config()
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
                    ft.Text(f"[{r.status}] {r.input_path.name}{suffix}", color=color, size=SZ_BODY)
                )
            state["last_results"] = results
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
        log(f"开始处理 {len(state['files'])} 个文件 (device={device_dd.value}, vad={vad_dd.value})")
        threading.Thread(target=run_pipeline, daemon=True).start()

    start_btn.on_click = on_start

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

    # === task view (米哈游式分组卡: 文件 / 运行 / 结果 / 日志) ===
    task_view = ft.Column(
        [
            section("任务", "跑转录 + 翻译管线，输出中日双语字幕", ft.Icons.FAVORITE),
            card(
                ft.Container(
                    ft.Column(
                        [
                            field_label("输入文件"),
                            ft.Row([add_btn]),
                            ft.Container(file_list, padding=ft.Padding(left=4, top=4, right=4, bottom=4)),
                        ],
                        spacing=S_ITEM,
                    ),
                    padding=S_CARD,
                )
            ),
            card(
                ft.Container(
                    ft.Column(
                        [
                            field_label("运行"),
                            ft.Row([to_switch, limit_field]),
                            ft.Row([start_btn, open_btn]),
                            progress,
                            status,
                        ],
                        spacing=S_ITEM,
                    ),
                    padding=S_CARD,
                )
            ),
            ft.Text("结果", size=SZ_SECTION, weight=ft.FontWeight.BOLD, color=C_TEXT),
            done_list,
            ft.Text("日志", size=SZ_SECTION, weight=ft.FontWeight.BOLD, color=C_TEXT),
            log_view,
        ],
        spacing=S_SEC,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )

    # === transcribe view ===
    model_status = ft.Column(spacing=4)

    def refresh_models(_=None):
        missing = check_model_readiness(config, transcribe_only=to_switch.value)
        model_status.controls.clear()
        if missing:
            for m in missing:
                model_status.controls.append(ft.Text(f"[X] {m}", color=ft.Colors.RED, size=SZ_BODY))
        else:
            model_status.controls.append(
                ft.Text("所有必需模型路径存在", color=C_SECONDARY, size=SZ_BODY, weight=ft.FontWeight.BOLD)
            )
        model_status.controls.append(ft.Divider())
        model_status.controls.append(ft.Text("模型路径", size=SZ_SECTION, weight=ft.FontWeight.BOLD, color=C_TEXT))
        for k, v in config.settings["models"].items():
            p = config.path_from_root(v)
            exists = p.exists()
            mark = "OK" if exists else "X"
            color = C_SECONDARY if exists else ft.Colors.RED
            model_status.controls.append(ft.Text(f"[{mark}] {k}: {v}", color=color, size=12, selectable=True))
        page.update()

    check_btn = ft.ElevatedButton("重新检查", icon=ft.Icons.REFRESH, on_click=refresh_models)

    transcribe_view = ft.Column(
        [
            section("转录", "ASR / VAD / 设备配置"),
            card(
                ft.Container(
                    ft.Column(
                        [
                            field_label("ASR 设备"),
                            device_dd,
                            field_label("VAD preset"),
                            vad_dd,
                        ],
                        spacing=S_ITEM,
                    ),
                    padding=S_CARD,
                )
            ),
            card(
                ft.Container(
                    ft.Column(
                        [
                            ft.Row([field_label("模型就绪"), check_btn]),
                            model_status,
                        ],
                        spacing=S_ITEM,
                    ),
                    padding=S_CARD,
                )
            ),
        ],
        spacing=S_SEC,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )

    # === translate view ===
    def test_api(_):
        test_result.value = "测试中..."
        test_result.color = None
        page.update()

        def run():
            ok, msg = preflight_api(endpoint_field.value, model_field.value, api_key_field.value)
            test_result.value = f"[{'OK' if ok else 'FAIL'}] {msg}"
            test_result.color = C_SECONDARY if ok else ft.Colors.RED
            page.update()

        threading.Thread(target=run, daemon=True).start()

    test_btn = ft.ElevatedButton("API 测试", icon=ft.Icons.SEND, on_click=test_api)

    translate_view = ft.Column(
        [
            section("翻译", "API 端点 / 模型 / 提示词"),
            card(
                ft.Container(
                    ft.Column(
                        [
                            field_label("API 配置"),
                            endpoint_field,
                            model_field,
                            profile_dd,
                            api_key_field,
                            ft.Row([test_btn, test_result]),
                        ],
                        spacing=S_ITEM,
                    ),
                    padding=S_CARD,
                )
            ),
        ],
        spacing=S_SEC,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )

    # === dictionary view ===
    dict_dir = ROOT / "dictionaries"

    def load_dict(filename):
        p = dict_dir / filename
        return p.read_text(encoding="utf-8") if p.exists() else ""

    def make_dict_card(title, hint, filename, lines=8):
        field = ft.TextField(
            multiline=True,
            min_lines=lines,
            max_lines=lines,
            value=load_dict(filename),
            width=620,
        )
        save_status = ft.Text("", size=12)

        def save(_):
            (dict_dir / filename).write_text(field.value or "", encoding="utf-8")
            save_status.value = "已保存"
            save_status.color = C_SECONDARY
            page.update()

        save_btn = ft.ElevatedButton("保存", icon=ft.Icons.SAVE, on_click=save)
        return card(
            ft.Container(
                ft.Column(
                    [
                        ft.Row([ft.Text(title, size=SZ_SECTION, weight=ft.FontWeight.BOLD, color=C_TEXT), save_btn, save_status]),
                        ft.Text(hint, size=11, color=C_SUB),
                        field,
                    ],
                    spacing=8,
                ),
                padding=S_CARD,
            )
        )

    dictionary_view = ft.Column(
        [
            section("字典 / 后处理", "术语字典与译后替换"),
            make_dict_card(
                "转录修正 (transcription_corrections.txt)",
                "格式: 日文=>修正后日文  或  日文<TAB>修正后日文",
                "transcription_corrections.txt",
            ),
            make_dict_card(
                "翻译术语 (translation_glossary.txt)",
                "格式: 日文<TAB>中文 (GalTransl GPT字典, TAB分隔, 每行一条)",
                "translation_glossary.txt",
            ),
            make_dict_card(
                "译后替换 (post_translation_replacements.txt)",
                "格式: 中文=>替换后中文  或  中文<TAB>替换后中文",
                "post_translation_replacements.txt",
            ),
        ],
        spacing=S_SEC,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )

    # === log view (圆角容器 + ListView) ===
    log_file_dd = ft.Dropdown(label="选择文件查看 run.log", width=420)
    log_list = ft.ListView(expand=True, spacing=0, auto_scroll=True, padding=4)
    log_display = ft.Container(
        log_list,
        border_radius=R_BOX,
        bgcolor=C_BG,
        padding=12,
        height=420,
    )

    def show_run_log(_=None):
        name = log_file_dd.value
        log_list.controls.clear()
        if not name:
            page.update()
            return
        for r in state.get("last_results", []):
            if r.input_path.name == name:
                run_log_path = r.output_dir / "cache" / "run.log"
                content = run_log_path.read_text(encoding="utf-8") if run_log_path.exists() else "(无 run.log)"
                for line in content.splitlines():
                    log_list.controls.append(ft.Text(line, size=12, selectable=True, color=C_TEXT))
                break
        page.update()

    log_file_dd.on_change = show_run_log

    def refresh_log_page():
        results = state.get("last_results", [])
        log_file_dd.options = [ft.dropdown.Option(r.input_path.name) for r in results]
        if results:
            log_file_dd.value = results[0].input_path.name
        show_run_log()

    def open_log_dir(_):
        name = log_file_dd.value
        if not name:
            return
        for r in state.get("last_results", []):
            if r.input_path.name == name:
                if sys.platform == "win32":
                    os.startfile(str(r.output_dir))
                else:
                    subprocess.Popen(["xdg-open", str(r.output_dir)])
                break

    log_open_btn = ft.ElevatedButton("打开输出目录", icon=ft.Icons.FOLDER_OPEN, on_click=open_log_dir)

    log_view_page = ft.Column(
        [
            section("日志", "历史运行日志查看"),
            card(
                ft.Container(
                    ft.Column(
                        [
                            ft.Row([log_file_dd, log_open_btn]),
                            log_display,
                        ],
                        spacing=S_ITEM,
                    ),
                    padding=S_CARD,
                )
            ),
        ],
        spacing=S_SEC,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )

    # === navigation (MD3 NavigationRail) ===
    content_area = ft.Container(task_view, expand=True, padding=ft.Padding(left=28, top=28, right=28, bottom=28))

    def nav_change(e):
        idx = e.control.selected_index
        views = [task_view, transcribe_view, translate_view, dictionary_view, log_view_page]
        content_area.content = views[idx]
        if idx == 4:
            refresh_log_page()
        page.update()

    rail = ft.NavigationRail(
        selected_index=0,
        destinations=[
            ft.NavigationRailDestination(icon=ft.Icons.PLAY_CIRCLE_OUTLINE, selected_icon=ft.Icons.PLAY_CIRCLE, label="任务"),
            ft.NavigationRailDestination(icon=ft.Icons.GRAPHIC_EQ, label="转录"),
            ft.NavigationRailDestination(icon=ft.Icons.TRANSLATE, label="翻译"),
            ft.NavigationRailDestination(icon=ft.Icons.MENU_BOOK, label="字典"),
            ft.NavigationRailDestination(icon=ft.Icons.DESCRIPTION, label="日志"),
        ],
        on_change=nav_change,
    )

    page.add(ft.Row([rail, ft.VerticalDivider(width=1), content_area], expand=True))
    refresh_models()


if __name__ == "__main__":
    ft.app(target=main)