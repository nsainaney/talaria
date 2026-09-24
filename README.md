# Talaria

iOS chat client for a [hermes-agent](https://github.com/nousresearch/hermes-agent) gateway, speaking the native Hermes API server directly.

## Server setup

Talaria speaks the `tui_gateway` JSON-RPC protocol over the dashboard's WebSocket, the same backend the Hermes TUI and Desktop app use. Run `hermes dashboard` bound to a reachable address with a username/password provider:

```
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=you
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=...
HERMES_DASHBOARD_BASIC_AUTH_SECRET=<openssl rand -base64 32>
```

In the app, open Settings (gear), enter the dashboard URL (e.g. `http://prometheus:9119`), username and password, and Sign in. The password is stored in the Keychain; the dashboard session cookies renew themselves and the app re-signs in silently if they lapse. Sign out clears both. Requires Hermes 0.21 or newer.

## Protocol

| Purpose | Call |
|---|---|
| Sign in / WebSocket ticket | `POST /auth/password-login`, `POST /api/auth/ws-ticket`, then `ws://host/api/ws?ticket=…` |
| Sessions | `session.list`, `session.resume`, `session.create`, `session.title`, `session.close` + `session.delete` |
| Turns | `prompt.submit`, `session.steer`, `session.interrupt` |
| Attachments | `image.attach_bytes`, `file.attach` |
| Skills | `skills.manage list` + `complete.slash` for descriptions; `/name args` runs through `command.dispatch` |
| Streaming | events `message.start/delta/complete`, `reasoning.delta/available`, `tool.start/complete`, `status.update`, `session.title`, `sessions.changed` |
| Prompts from the agent | server requests `approval` and `clarify`, answered in place |
| Reconnect | per-session `seq` watermarks and `session.events.since` replay; `session.resume` re-attaches to a live turn |

Pinned sessions and skills are stored locally in UserDefaults, not on the server (iCloud sync needs a paid team).

## Layout

- `talaria/Networking` – `GatewayAuth` (dashboard login, tickets), `GatewayClient` (JSON-RPC over WebSocket, replay), `Keychain`, `ImageEncoding`
- `talaria/State` – `AppModel`, `ChatStore` (events → transcript rows), `SkillsStore`, `PinStore`, `ServerSettings`
- `talaria/Views` – `RootView`, `ChatView`, `ChatRow`, `SessionsSidebar`, `SkillsView`, `SettingsView`, `ApprovalView` (+ `ClarifyView`)

`Info.plist` allows plain-HTTP loads so LAN dashboards work; deployment target is iOS 26.5.

## Voice (branch `voice`)

Everything runs on the phone; nothing new is needed on the server.

- **Talk to Hermes.** Tap the microphone in the composer. Speech is recognised on the phone and
  sent as text after a short pause; replies are spoken sentence by sentence as they stream, with
  code blocks and markdown stripped. Talk over a reply and it goes quiet and listens; anything said while Hermes is working is
  steered into the running turn (queued if the turn is too far along); say "stop" to interrupt. Permission and clarify requests are read aloud and take a spoken *allow*,
  *always* or *deny* (the on-screen popup still works).
- **Record a meeting.** Composer `+` menu → *Record meeting*. Audio is saved to
  Files › Talaria › Meetings and transcribed live on the phone in timestamped segments,
  including with the screen locked. *Send to Hermes* attaches the transcript with an
  instruction. If a `meeting-digest` skill exists on the server the app invokes it instead.
- **Server skill.** Copy `hermes/skills/meeting-digest/` to
  `~/.hermes/skills/productivity/meeting-digest/` on the Hermes host (on prometheus that home is
  `/mnt/space/services/hermes/state`) and reload skills. It uses the `memory` and
  `cronjob_manage` tools and asks before creating reminders.
- **Server voice (Pocket TTS).** With *Hermes voice* on in Settings, each spoken sentence is
  fetched from the dashboard's `POST /api/audio/speak`, which runs the profile's TTS provider.
  On prometheus that is Kyutai's reference Pocket TTS served warm by the nix-managed
  `podman-pocket-tts` container on 127.0.0.1:8131, declared in nix-config
  `services/hermes/pocket-tts.nix` together with the `say-http` wrapper Hermes calls and the
  `tts` provider block (voice `vera`). A warm sentence takes 0.3 to 1 s. Change the voice by
  editing `voice` there and deploying. `hermes/pocket-tts/` in this repo keeps the Dockerfile
  and wrapper source for reference. If the
  server cannot synthesize, the phone voice takes over for the rest of the reply.
  (The `pocket-tts.cpp` bundle from the benchmark is still there as `say`, but its
  end-of-speech detection babbles on short text, so it is no longer used.)
- **Turning it off.** Settings → *Voice mode* hides the microphone and the meeting entry. To
  drop the feature entirely, delete the branch: `git checkout main && git branch -D voice`.

Known limits: no speaker labels, English-first, and replies from Hermes take one to two seconds
plus whatever its tools take. The voice engine is `SFSpeechRecognizer`; iOS 26's
`SpeechAnalyzer` would be the upgrade for long meetings.

## Recorder widget and Speakr (branch `voice`)

Settings › Speakr takes the Speakr server URL and an API token (created in Speakr under your account's API tokens; kept in the Keychain).

**Recorder widget.** Add the "Recorder" widget to the Home Screen or Lock Screen, or the "Record to Speakr" control to Control Center. Start, Pause, Resume and Stop run in the app process (App Intents conforming to `AudioRecordingIntent`), so the app need not be open. Recording shows as a Live Activity in the Dynamic Island and on the Lock Screen with the same buttons. A phone or FaceTime call pauses the recording; it resumes on its own when the call ends. Stop uploads the file to Speakr on a background transfer (`POST /api/v1/recordings/upload`); the widget, Live Activity and the strip in the app show "Sent to Speakr as recording #N" or why it was not sent. The audio always stays in Files › Talaria › Meetings. The in-app "Record meeting" flow (live transcript to Hermes) also gets a "Send to Speakr" button.

First run: the app must have been granted the microphone once; until then the widget's Record button opens the app (`talaria://record`) to ask. Both targets share the App Group `group.com.sainaney.talaria`; if Xcode complains about the provisioning profile, tick App Groups in Signing & Capabilities for both targets once so it registers the group.

Layout: `Shared/` (state, intents, Live Activity attributes; compiled into both targets), `TalariaWidget/` (widget, Live Activity, control), `talaria/Recording/` (recorder, background uploader). The widget target's Info.plist is `TalariaWidget-Info.plist` at the repo root.
