# whisper.cpp 使用说明

- 请下载[WhisperCpp](https://github.com/ggml-org/whisper.cpp/releases)放到这个文件夹，确保包含`whisper-cli`可执行文件。
- 请下载[Silero-VAD](https://huggingface.co/ggml-org/whisper-vad/tree/main)放到这个文件夹，确保包含`ggml-silero-v5.1.2.bin`文件。
- 可选日语动漫优化模型: 下载 [ggml-whisper-ja-anime-v0.3-f16.zip](https://github.com/yangyucitrus/VoiceTransl/releases/download/v1.14-vad/ggml-whisper-ja-anime-v0.3-f16.zip)，解压后将 `.bin` 文件放入此文件夹。
  - 基于 whisper-large-v3-turbo 微调，专门优化日语动漫识别
  - 词表缩小至 20480 (~1.6x bytes/token)，解码速度更快
  - f16 格式，~1.47GB