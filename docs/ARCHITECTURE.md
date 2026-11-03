# Architecture

## Layout

```
App/Sources/
  MeetingTranscriberApp.swift   App entry, SwiftData container
  Model/Recording.swift         SwiftData model (CloudKit-compatible)
  Storage/AudioStorage.swift    File locations + Data Protection
  Recording/AudioRecorder.swift AVAudioEngine capture, session, interruptions
  Recording/SilenceTrimmer.swift  Post-stop silence removal → AAC
  Library/RecordingProcessor.swift  Finalize + crash recovery
  Library/ImportService.swift   Files / Voice Memos / drag & drop / Open-in
  Playback/AudioPlayer.swift
  Views/…                       Voice Memos–style UI
  Settings/…
Packages/MTCore/                Pure Swift (no AVFoundation): PCM I/O, silence
                                detector, time map, source detection, formatting
```

## Recording pipeline

1. **Capture** — `AVAudioEngine` input tap → `AVAudioConverter` → 16 kHz mono Int16 →
   appended to a *headerless* `.pcm` file. Every byte on disk is valid audio, so a crash
   or forced quit loses at most the last ~0.25 s. On next launch, `recoverInterrupted`
   finalizes any leftover capture.
2. **Lock screen** — `UIBackgroundModes: audio` + active `.record` session. Files use
   `completeUntilFirstUserAuthentication` protection (encrypted at rest, writable while locked).
3. **Interruptions** — calls/Siri pause the engine (iOS does not allow recording during a call);
   on `.ended`, on return to foreground, or on route/config change the engine is rebuilt and
   capture continues into the same file (retried for ~10 s). Media-services reset rebuilds the engine.
4. **Stop → trim** — frame energies (30 ms) → adaptive threshold (noise floor + 10 dB,
   clamped −60…−30 dBFS) → silences ≥ 2 s (configurable) removed, keeping 0.3 s padding and
   10 ms fades at cuts → AAC `.m4a` (~10× smaller than raw). The raw file is deleted only after
   a successful encode. A `TimeMap` maps trimmed times back to the original timeline.

   *Note:* stage 1 uses this energy detector (dependency-free, conservative). Stage 2 adds
   FluidAudio, whose Silero VAD can replace it if trimming proves too timid or too aggressive.

## Import

- Files app / Finder: `fileImporter`, drag & drop.
- Voice Memos: its Share sheet lists this app (declared audio document types → "Open in").
  No Share Extension is needed, so it works without a paid developer account.
- Badge: `RecordingSource` = `inApp | files | voiceMemos | shared`. Voice Memos is detected from
  the Mac storage path or default memo file names ("New Recording N", "הקלטה חדשה N",
  "yyyyMMdd HHmmss"). A renamed memo shared from Voice Memos shows as "Imported".

## Decisions (approved)

- iOS/iPadOS/macOS 26 minimum, native SwiftUI (not Catalyst).
- Transcription: on-device WhisperKit + ivrit.ai Whisper large-v3-turbo + FluidAudio diarization;
  cloud ElevenLabs Scribe (default cloud). Providers behind a `TranscriptionProvider` protocol.
- Proofreading: Claude (Sonnet default, Opus optional), segment-ID-preserving JSON with validation.
- Email: `MFMailComposeViewController` (iOS/iPadOS), `NSSharingService(.composeEmail)` (macOS).
- iCloud sync: wanted — requires the paid Developer Program; model is ready for it.
- No vendor SDKs, no telemetry. Keys in Keychain (`WhenUnlockedThisDeviceOnly`).
