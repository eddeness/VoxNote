# VoxNoteAI

On-device voice notes for iPhone and Mac. Record audio, transcribe it, summarize it, and translate it without sending speech to a server.

The first launch downloads the speech and language models. After that, recording, transcription, and summarization work offline. Translation uses Apple’s on-device Translation framework and may download a language pack the first time a pair is used.

## Features

- Record from the microphone to WAV (44.1 kHz, mono), up to 3 hours
- Organize recordings in nested folders, rename them, and move them between folders
- Transcribe saved recordings with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (word timestamps, language selection)
- Live transcription while recording (a separate window on macOS, full screen on iOS)
- Summarize a transcript on device with a Qwen 2.5 model via [MLX](https://github.com/ml-explore/mlx-swift-examples)
- Translate a transcript with Apple Translation
- Play recordings back in the list
- Export a transcript as plain text or SRT

## Requirements

- Xcode 26 or later
- iOS 26 / macOS 15
- Apple silicon recommended (WhisperKit and MLX)
- Microphone permission
- Internet only for the first model download
- Free disk space: about 4 GB on Mac, about 2 GB on iPhone (the onboarding screen checks this)

## Getting started

1. Open `VoxNote.xcodeproj`.
2. Let Xcode resolve Swift packages:
   - [WhisperKit](https://github.com/argmaxinc/WhisperKit) (`main`)
   - [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) (2.29.1+)
3. Select an iPhone or Mac destination and run.
4. On first launch, download the speech model from the welcome screen.

The app display name is **VoxNoteAI**. The bundle identifier is `seungpark.VoxNote`.

## Models

The app picks a model from available RAM so smaller devices stay usable.

| |  Higher RAM | Lower RAM |
|---|---|---|
| Transcription (Mac) | `openai_whisper-small` at 15 GB+ | `openai_whisper-base` |
| Transcription (iPhone) | `openai_whisper-base` at 5 GB+ | `openai_whisper-tiny` |
| Summary (Mac) | Qwen2.5-7B-Instruct 4-bit at 16 GB+ | Qwen2.5-3B-Instruct 4-bit |
| Summary (iPhone) | Qwen2.5-3B-Instruct 4-bit at 6 GB+ | Qwen2.5-1.5B-Instruct 4-bit |

Whisper weights come from `argmaxinc/whisperkit-coreml`. Summary weights come from `mlx-community` and are downloaded the first time you summarize.

## How it is organized

SwiftUI app with one `MainViewModel` and small services.

```
VoxNote/
  VoxNoteApp.swift          App entry, SwiftData container, macOS live window
  MainView.swift             Library, folders, record controls
  MainViewModel.swift        Recording, folders, transcription, summary, translation state
  Service/
    AudioCaptureService      Microphone capture and WAV files
    TranscriptService        WhisperKit file transcription
    LiveTranscriptionService Rolling-window live transcription
    LocalLLMService          On-device summarization
    AudioPlayerService       Playback
    ExportService            TXT and SRT export
  Model/                     Recording, folder, transcript, metadata
  Component/                 Rows, onboarding, live view, pickers
```

Audio files live in `Documents/Recordings/` as `rec_<timestamp>.wav`. Names, transcripts, summaries, translations, and folders are stored with SwiftData (`RecordingMetadata`, `RecordingFolder`) and joined to files by filename.

## Privacy

Microphone audio stays on the device. Transcription and summarization run locally. The only network use is downloading models (and Apple’s translation language packs, when needed). The Mac target is sandboxed and requests microphone input.
