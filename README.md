# Talaria

iOS chat client for a [hermes-agent](https://github.com/nousresearch/hermes-agent) gateway, speaking the native Hermes API server directly.

## Server setup

In `~/.hermes/.env`:

```
API_SERVER_ENABLED=true
API_SERVER_KEY=<your key>
API_SERVER_HOST=0.0.0.0   # if the phone is on the LAN rather than the same machine
```

Then `hermes gateway`. In the app, open Settings (gear) and enter the base URL (default `http://127.0.0.1:8642`) and the key.

## Hermes endpoints used

| Purpose | Endpoint |
|---|---|
| List / create / delete sessions | `GET|POST /api/sessions`, `DELETE /api/sessions/{id}` |
| Session history | `GET /api/sessions/{id}/messages?order=oldest` |
| Send a turn | `POST /v1/runs` `{input, session_id, conversation_history}` |
| Stream the turn | `GET /v1/runs/{id}/events` (SSE; `message.delta`, `reasoning.available`, `tool.started`, `tool.completed`, `approval.request`, `run.completed` …) |
| Poll a run after reconnect | `GET /v1/runs/{id}` |
| Steer a running turn | `POST /v1/runs/{id}/steer` `{input}` |
| Stop | `POST /v1/runs/{id}/stop` |
| Rename / pin a session | `PATCH /api/sessions/{id}` `{title}` or `{pinned}` |
| Answer a permission prompt | `POST /v1/runs/{id}/approval` `{choice, request_id?}` |
| Skills | `GET /v1/skills` |
| Connection test | `GET /health` |

The app sends its own transcript as `conversation_history` on every run. The Hermes build on the server (0.19.0) does not load a session's history for `/v1/runs` by itself, although newer builds do; supplying it explicitly works on both and the turn is still written to the session.

Images are sent as `data:image/jpeg;base64,…` parts inside an OpenAI-style user message in the run `input`. Hermes drops a run's event queue once the client disconnects, so after backgrounding the app polls the run status and then reloads the session transcript.

Skill invocation: the API server does not expand `/skill` slash commands (only the CLI and messaging gateways do), so `/name …` in the composer is sent as an explicit instruction asking the agent to load that skill.

## Layout

- `talaria/Networking` – `HermesClient` (REST + SSE), `SSEParser`, `Keychain`
- `talaria/State` – `AppModel`, `ChatStore` (event stream → transcript rows), `SkillsStore` (search + pins), `ServerSettings`
- `talaria/Views` – `RootView` (sessions drawer, toolbar), `ChatView` (transcript, composer, `/` popup), `ChatRow`, `SkillsView`, `SettingsView`, `ApprovalView`

`Info.plist` (project root) allows plain-HTTP loads so LAN gateways work; deployment target is iOS 26.5.
