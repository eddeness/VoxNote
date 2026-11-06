# Roadmap

VoxNoteAI is a private voice-note app for iPhone and Mac. The goal is to make recordings useful after the conversation ends: capture them reliably, turn them into readable notes on the device, and help people find what matters later.

This roadmap reflects the current codebase and planned work. Items are ordered by priority, not by a promised release date. Checkboxes describe what is implemented; they do not imply that every workflow has been fully tested on all devices.

## Built so far

- [x] Record microphone audio as local WAV files and play saved recordings.
- [x] Organize recordings in nested folders, rename them, and move them between folders.
- [x] Transcribe saved audio with WhisperKit, language selection, and timestamps.
- [x] Show a live transcript while recording.
- [x] Summarize transcripts locally with a Qwen model through MLX.
- [x] Translate transcripts with Apple's Translation framework.
- [x] Store recording names, transcripts, and summaries with SwiftData.
- [x] Choose smaller speech and summary models on devices with less memory.

## Next: Trustworthy capture and notes

- [ ] Give each recording a stable identity across app launches and library refreshes.
- [ ] Keep the stop-recording control available while other processing is running; handle window closure and audio-write failures safely.
- [ ] Make transcription, summarization, and translation tasks cancel cleanly when a recording is removed or an operation is retried.
- [ ] Report persistence failures and restore saved translations with their target languages.
- [ ] Finish the last live-transcription segment when recording stops and remove duplicate or stale live text.
- [ ] Connect the existing TXT and SRT export code to a working export action on both platforms.
- [ ] Add focused tests for recording identity, saving, cancellation, playback, and export.

## Then: Get more from a recording

- [ ] Import existing audio files, including recordings made in other apps.
- [ ] Mark important moments during a recording and review those moments afterward.
- [ ] Tap a transcript segment to play from its timestamp and search across saved transcripts.
- [ ] Summarize long recordings in sections, then combine the sections into a useful overview.
- [ ] Ask questions about a recording and show the transcript passages that support each answer.

## Later: Personal and private workflows

- [ ] Let users maintain a personal vocabulary for names and technical terms that transcription often gets wrong.
- [ ] Offer a review step to hide names, contact details, or other sensitive text before sharing a transcript.
- [ ] Support distinct note formats for meetings, lectures, interviews, and personal ideas.

The priority is to make existing recordings and notes dependable before expanding the number of AI features. Feature scope and order may change as the app is tested on real devices.
