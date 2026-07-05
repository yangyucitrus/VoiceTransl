# Context

This fork narrows VoiceTransl into a Japanese ASMR subtitle workbench. It is not a general video downloader, media toolbox, or multilingual transcription app.

## Domain Terms

- Subtitle workbench: The product shape for this fork. It focuses on local audio/video files, Japanese ASMR transcription, Chinese subtitle translation, dictionaries, post-processing, logs, and repeatable output.
- ASMR transcription: The first-class local pipeline that converts Japanese ASMR/adult voice audio into Japanese timed subtitle data.
- ASMR VAD: Voice activity detection tuned for Japanese ASMR, whispering, quiet speech, long pauses, breaths, and soft vocalizations. The preferred implementation is TransWithAI's Whisper VAD ONNX model.
- Transcription JSON: The Japanese timed JSON generated from ASR. It is a first-class artifact, not a temporary implementation detail.
- Translation JSON: The Chinese timed JSON generated after translation. It remains compatible with GalTransl-style translation output.
- Transcription correction dictionary: A deterministic dictionary applied to Japanese transcription output for known ASR mistakes, names, circle names, and fixed terms.
- Translation glossary: The terms and naming guidance passed to the online translation model so character names, relationship terms, and repeated concepts translate consistently.
- Post-translation replacement dictionary: A deterministic dictionary applied to Chinese output after translation.
- Quality report: A lightweight deterministic report that flags obvious transcription and translation problems such as empty text, repeated segments, overlapping timestamps, leftover Japanese, and malformed output.

## Product Defaults

- Input is local audio/video files only.
- Primary source language is Japanese.
- Primary content style is ASMR/adult voice works with 2D/anime tone.
- Primary output is Japanese SRT, Chinese SRT, bilingual SRT, transcription JSON, and translation JSON.
- Batch processing is supported, but v1 runs files serially.
- Existing caches are reused by default.
- Models are placed manually under `models/`; v1 does not download large models from the UI.
- Configuration is preset-driven. The GUI should expose ASR engine, VAD preset, and device preset choices instead of raw model or VAD parameters.
- `.env` stores only secrets such as `VOICETRANSL_API_KEY`; `settings.yaml` stores product settings such as endpoint, model, presets, cache behavior, and model paths.

## Translation Style

Default Chinese translation style is natural adult-oriented spoken subtitle Chinese with moderate 2D/anime tone. It should be lightly polished but faithful, clear about adult content when the source is clear, and should not add vulgarity or extra intensity that is absent from the original.
