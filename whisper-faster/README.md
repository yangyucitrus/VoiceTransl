# Faster-Whisper-XXL

请下载 [Faster-Whisper-XXL](https://github.com/Purfview/whisper-standalone-win/releases/latest) 的可执行文件，将其重命名为 `whisper-faster.exe` 并放到此文件夹，同时将 `_xxl_data/` 文件夹也放入此文件夹。

注意：VAD 功能仅 Faster-Whisper-XXL 支持，普通 Faster-Whisper 不支持。推荐使用 Faster-Whisper-XXL。

## 命令行参数说明

### 基础参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--model` / `-m` | 模型名称 (如 `turbo`, `small`, `medium`, `large-v3`) | `medium` |
| `--model_dir` | 模型目录 (`_models/` 或自定义) | `_models/` |
| `--language` / `-l` | 语言代码 (`ja`, `en`, `zh`, `ko`, `ru`, `fr` 等) | `auto` |
| `--task` | 任务类型 (`transcribe` 听写 / `translate` 翻译为英文) | `transcribe` |
| `--output_format` | 输出格式 (`srt`, `vtt`, `txt`, `json`, `tsv`, `csv`) | `srt` |
| `--output_dir` / `-o` | 输出目录 | 音频文件所在目录 |
| `--compute_type` | 计算类型 (`float16`, `int8`, `int8_float16`, `int8_bfloat16`, `auto` / `default`) | `default` |
| `--device` | 计算设备 (`cuda` / `cpu`)，默认自动 | auto |
| `--verbose` | 详细日志 (`True` / `False`) | `False` |
| `--beep_off` | 关闭完成提示音 | off |

### VAD (语音活动检测) 参数

| 参数 | 说明 | 可选值 / 默认值 |
|------|------|-----------------|
| `--vad` | 启用 VAD | `True` / `False` (默认 `False`) |
| `--vad_method` | VAD 方法 | `silero_v3`, `silero_v4`, `silero_v5`, `pyannote_v3`, `pyannote_onnx_v3`, `auditok`, `webrtc` (默认 `silero_v5`) |
| `--vad_threshold` | VAD 阈值，越高越严格 | `0.0` ~ `1.0` (默认 `0.5`) |
| `--vad_min_silence_duration_ms` | 最小静音间隔 (毫秒) | 默认 `500` |
| `--vad_speech_pad_ms` | 语音段前后填充 (毫秒) | 默认 `400` |
| `--vad_filter_speechless_segments` | 过滤无语音段 | `True` / `False` |
| `--vad_max_speech_duration_s` | 最大语音段时长 (秒) | 默认 `20` |

### 转录调优参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--temperature_increment_on_fallback` | 回退温度增量 | `0.2` |
| `--best_of` | 采样数量（可用于提高质量） | `1` |
| `--beam_size` | 束搜索大小 | `5` |
| `--word_timestamps` | 词级时间戳 | `True` |
| `--condition_on_previous_text` | 基于前文的条件转录 | `True` |
| `--repetition_penalty` | 重复惩罚系数 | `1.0` |
| `--no_speech_threshold` | 无语音段检测阈值 | `0.6` |
| `--logprob_threshold` | 对数概率阈值 | `-1.0` |
| `--compression_ratio_threshold` | 压缩比阈值 | `2.4` |
| `--initial_prompt` | 初始提示词 | 空 |
| `--hotwords` | 热词，逗号分隔 | 空 |

### VAD 方法说明

- **silero_v3/v4/v5**: Silero VAD 模型 (推荐，无需额外下载)
- **pyannote_v3**: PyAnnote 模型 (需要额外下载模型文件)
- **pyannote_onnx_v3**: PyAnnote ONNX 模型 (需要额外下载模型文件)
- **auditok**: 基于能量的 VAD
- **webrtc**: WebRTC VAD

### 使用建议

1. **日语转录**: 设置 `--language ja --vad_min_silence_duration_ms 500`
2. **英语转录**: 设置 `--language en --vad_threshold 0.4`
3. **嘈杂环境**: 设置 `--vad_threshold 0.6 --vad_min_silence_duration_ms 300`
4. **提高精度**: 设置 `--beam_size 5 --best_of 3 --temperature_increment_on_fallback 0.2`
5. **提高速度**: 设置 `--vad False --compute_type int8_float16 --beam_size 1`
