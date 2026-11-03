# Device test checklist

CI covers compilation and logic tests on macOS, iPhone and iPad simulators. These checks
need real hardware. Report results (✅/❌ + notes) per device.

## Stage 1 — Recording & file list

### iPhone and iPad
1. First launch → tap record → microphone permission prompt appears; allow.
2. Record 30 s while speaking. Timer runs, waveform moves; the new row appears at the top of the list immediately with status **Recording** and a live duration.
3. **Pause / resume**: timer stops while paused and continues afterwards.
4. **Lock screen**: start recording, lock the device for 2 minutes while talking, unlock. Duration ≈ wall-clock time; playback contains the speech from while it was locked.
5. **Phone call**: while recording, receive a call (or FaceTime audio) and decline/finish it. Status shows "Paused by a call or Siri", then recording resumes by itself. Nothing recorded before the call is lost.
6. **Siri**: while recording, invoke Siri, then dismiss. Recording resumes.
7. **Silence trimming**: record ~20 s talking, 15 s total silence, ~20 s talking. After stop: status goes **Processing → New**; the detail screen shows "Silence removed ≈ 0:14"; playback has no long gap and no words cut off.
8. **Crash safety**: start recording, talk 20 s, force-quit the app from the app switcher. Relaunch → the recording is recovered and processed (status **New**, ≈20 s).
9. **List**: rename (swipe or long-press), delete, search by name.
10. **Import from Files**: Import button → choose an audio file → appears with a purple **Imported** badge.
11. **Import from Voice Memos**: Voice Memos → a memo → Share → Transcriber (or *More…* if not shown). Appears with a **Voice Memos** badge (an **Imported** badge if the memo was renamed).
12. Playback controls (play/pause, ±15 s, scrubbing) work.

### Mac
1. Record → microphone permission prompt → record 30 s → stop → row shows status **New** with duration and size.
2. Pause / resume; ⌘R starts/stops.
3. Unplug/plug headphones or change input device mid-recording → recording continues.
4. Drag an audio file from Finder onto the list → imported with badge.
5. Drag a memo out of the Voice Memos app onto the list → **Voice Memos** badge.
6. Rename, delete, search; playback.
