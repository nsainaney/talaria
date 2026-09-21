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
  code blocks and markdown stripped. Talk over a reply to stop it; say "stop" to interrupt a
  running turn. Permission and clarify requests are read aloud and take a spoken *allow*,
  *always* or *deny* (the on-screen popup still works).
- **Record a meeting.** Composer `+` menu → *Record meeting*. Audio is saved to
  Files › Talaria › Meetings and transcribed live on the phone in timestamped segments,
  including with the screen locked. *Send to Hermes* attaches the transcript with an
  instruction. If a `meeting-digest` skill exists on the server the app invokes it instead.
- **Server skill.** Copy `hermes/skills/meeting-digest/` to
  `~/.hermes/skills/productivity/meeting-digest/` on the Hermes host (on prometheus that home is
  `/mnt/space/services/hermes/state`) and reload skills. It uses the `memory` and
  `cronjob_manage` tools and asks before creating reminders.
- **Turning it off.** Settings → *Voice mode* hides the microphone and the meeting entry. To
  drop the feature entirely, delete the branch: `git checkout main && git branch -D voice`.

Known limits: no speaker labels, English-first, and replies from Hermes take one to two seconds
plus whatever its tools take. The voice engine is `SFSpeechRecognizer`; iOS 26's
`SpeechAnalyzer` would be the upgrade for long meetings.
