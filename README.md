# Meeting Transcriber

Personal app for iPhone, iPad and Mac (one SwiftUI codebase) that records meetings and
produces proofread Hebrew transcripts with speaker labels.

**Status:** Stage 1 of 4 — recording & file list. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

| Stage | Scope | State |
|---|---|---|
| 1 | Recording (lock screen, interruptions, silence trimming), file list, import | ✅ code complete — device testing |
| 2 | Transcription: on-device (WhisperKit + ivrit.ai, FluidAudio) and cloud (ElevenLabs Scribe), queue | ⏳ |
| 3 | Claude proofreading pass, raw + proofread versions | ⏳ |
| 4 | Transcript view/edit/search (RTL), speaker renaming, email, Keychain/settings/privacy | ⏳ |

## Build & run

Requirements: a Mac with **Xcode 26** and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

```bash
git clone https://github.com/shimonshaked-lab/meeting-transcriber.git && cd meeting-transcriber
```

```bash
xcodegen generate && open MeetingTranscriber.xcodeproj
```

In Xcode, select the **MeetingTranscriber** target › *Signing & Capabilities* › *Team* →
your **Personal Team** (sign in with your Apple ID under Xcode › Settings › Accounts).
Then pick **My Mac**, an iPhone or an iPad as the run destination and press ⌘R.

> The `.xcodeproj` is generated — don't commit it. Re-run `xcodegen generate` after pulling.

### Free Apple ID (no paid developer account) — what that means

| Works with a free Personal Team | Needs the paid Apple Developer Program ($99/yr) |
|---|---|
| Running on your Mac (no expiry) | **iCloud sync between devices** (CloudKit) |
| Running on iPhone/iPad from Xcode | Installs that don't expire after **7 days** |
| Background recording, microphone, Keychain | TestFlight / App Store |
| "Open in" / Share sheet import from Voice Memos | App Groups / Share Extensions |

The data model is already CloudKit-compatible; enabling sync later is a small change
(see `MeetingTranscriberApp.swift`).

## Tests

- `swift test --package-path Packages/MTCore` — platform-independent logic (silence detection, time map, PCM I/O, formatting).
- Xcode ⌘U — app tests (silence trimming → AAC end-to-end, import) on Mac / simulator.
- CI (GitHub Actions, `macos-26`) runs both on macOS, iPhone simulator and iPad simulator on every push.
- Device-only checks (microphone, lock screen, calls): [docs/TESTING.md](docs/TESTING.md).

## Privacy

No analytics, telemetry or third-party SDKs. In stage 1 nothing leaves the device at all.
