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
