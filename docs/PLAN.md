# Plan

From the comparison with Hermes Conduit (`~/Projects/forks/hermes-conduit`, MIT, commit e40c0fa) on
2026-10-02. Two lists: bugs to fix first, then things to adopt. Nothing here changes the frozen
design in `docs/design`.

How each item was checked is marked on it:

- **read** – confirmed by reading Talaria's code.
- **server** – also confirmed in the Hermes 0.21.3 source (`/nix/store/*-hermes-python-source`).
- **reported** – found by a reviewer, not re-checked. Confirm before fixing.

Nothing was run on a device. Conduit paths below are relative to its repo root.

## Fix first

All small. Order is by how often the bug is likely to be hit.

### 1. Gateway connection

- [ ] **Run-loop ownership.** After a credential or URL change, `connect(auth:)` starts a new loop,
  then the cancelled old loop exits and sets `runTask = nil`, so the next `connect()` starts a
  second loop. Two loops then fight over the socket. Clear `runTask` only when the exiting loop
  still owns it (compare a generation or the task identity). `GatewayClient.swift:111-117`, `:155`.
  *read*
- [ ] **State on drop.** When the socket closes, `state` stays `.connected` through the 1–1.5 s
  backoff sleep, so the send button is live and the send fails. Set `.reconnecting` as soon as
  `closed.value` returns. `GatewayClient.swift:144-153`. *read*
- [ ] **Foreground kick.** There is no scene-phase handling. On `.active`: interrupt the backoff
  sleep, and if a socket exists prove it with a `ping` on a 5 s timeout before trusting it. Then
  refresh the session list and resync the open chat. Also reload sessions and skills on every
  transition to connected, not only the first (`AppModel.swift:52-57` gives up after 10 s and never
  loads them). Conduit: `Conduit/Services/AppState.swift:10690-10832`. *read*
- [ ] **Stop on bad credentials.** `badCredentials` and `noProvider` only slow the loop, so a wrong
  password is retried every 30 s forever against an endpoint the server throttles
  (10 attempts per 60 s per IP). Stop the loop and show "Sign in again".
  `GatewayClient.swift:148`. *read, server (throttle seen in the 0.19 checkout)*
- [ ] **Expiry is more than 401.** `mintTicket` treats only 401 as expired. Treat 403 and a
  non-JSON login page the same way; show 429 as "too many attempts" with no retry.
  `GatewayAuth.swift:72-86`. *reported*

### 2. Opening a chat

- [ ] **Wrong chat after a failed open.** `open()` sets `session` only on success and `request`
  throws at once when the socket is down, so tapping chat B during a reconnect leaves chat A's
  transcript under B's page and sends go to A. Set the target before the await, fence overlapping
  opens with a generation counter, and retry once connected. `ChatStore.swift:103-119`,
  `ChatScreen.swift:18`, `:57-58`. *read*
- [ ] **Stale live id.** A reaped runtime answers `4001 session not found`. On that code from
  `prompt.submit` (or a failed `session.events.since`, which is swallowed today at
  `GatewayClient.swift:329`), resume the stored id, adopt the new live id and retry once.
  *server (the 4001 path); the reaper timing is not known*

### 3. Drafts

- [ ] **Restore on failure.** `sendDraft` and `submitWhileRunning` clear the draft before the RPC.
  Keep the text until the send is accepted, or put it back on failure. `ChatView.swift:296-310`,
  `ChatStore.swift:218-221`. *read*
- [ ] **Model picker wipes a new chat's draft.** The picker calls `ensureSession`, the session id
  changes, and `onChange` clears the draft and attachments. Clear only when moving between two
  existing sessions. `ChatView.swift:28`, `ChatStore.swift:319`, `:348`. *read*
- [ ] **Rejected steer.** The text is discarded when the server rejects a steer. Queue it instead,
  as `VoiceController` already does. `ChatView.swift:299`, `ChatStore.swift:403`. *read*
- [ ] **Per-session drafts.** Switching to voice or going back destroys the composer's state. Keep
  drafts in a small store keyed by session. Conduit's `ComposerDraftStore.swift` (113 lines, no
  dependencies) lifts nearly as-is; keep its MIT notice.

### 4. Server requests (approval, clarify and the rest)

The server can hold several open requests per session, and an error reply settles a request as
unanswered (`tui_gateway/server_requests.py`).

- [ ] **Queue by request id.** `pendingApproval` and `pendingClarify` are single slots; a second
  request overwrites the first, which is never answered, and that turn stalls until the server
  times out. Keep an ordered list, show the oldest, and reconcile it against `open_requests` after
  a resume or replay. Name the session on the sheet. `ChatStore.swift:52-53`, `:420-427`.
  *read, server*
- [ ] **Masked prompts.** `sudo`, `secret` and `vault.unlock_prompt` are refused with -32601, so
  the tool fails. Add a secure field; the reply is `{value}`. `ChatStore.swift:428`. *read, server*
- [ ] **Leave desktop-only requests alone.** `terminal.read`, `preview.read`, `preview.act`,
  `window.read` and `tour` can only be answered by a Hermes Desktop window. Replying with an error
  takes them away from it. Do not reply to these. (Conduit declines with 4404, which needs a
  server newer than 0.21.3: `declines_not_shown` and `client.capabilities` are not in this
  release.) `GatewayClient.swift:285-289`. *read, server*
- [ ] **Do not lose the answer.** The reply frame is sent with `try?` and the sheet is dismissed
  regardless. If the send fails, keep the request and say so. `GatewayClient.swift:240-244`,
  `ChatStore.swift:433-441`. *read*
- [ ] **Clear on server restart.** Drop pending requests when the replay epoch changes.

### 5. Voice

- [ ] **Echo filter eats the answer.** `isEcho` drops any utterance made mostly of words the phone
  spoke in the last 20 s. The approval prompt says "Say allow, …, deny", so those words are ignored
  right after it; the same happens with clarify options. The input is already muted while the
  phone talks, so bypass the filter while `answering != .none`, or remove it.
  `VoiceController.swift:216`, `:237`, `:363-371`, `:400`. *read*

### 6. Tasks

- [ ] **Triage is not a parking state.** The gateway auto-decomposes triage cards each dispatcher
  tick by default (`kanban.auto_decompose: True`, three per tick), so an "Agent" card can be
  rewritten, split and run without the grill. Set `kanban.auto_decompose: false` in nix-config
  (`services/hermes.nix`). `TasksStore.swift:157-167`; server `hermes_cli/config_defaults.py:1773`,
  `gateway/kanban_watchers.py:297-300`. *server; whether it is firing on prometheus is not known*
- [ ] **Stop does not stop.** Stop sends `status: scheduled`, which clears the claim and the
  worker pid without signalling the worker. Call `POST /tasks/{id}/reclaim` first, then schedule;
  the order matters because reclaim returns 409 once the claim is gone. Test live.
  `TasksStore.swift:280-283`; server `hermes_cli/kanban_db.py:3617-3643`. *server for the cause;
  the fix is reported*
- [ ] **Re-read before a status write.** `reply()`, `start()` and `proceed()` send `ready` from the
  client's snapshot. On a card that has since started running this kills and requeues the worker;
  on a done card it reopens it. GET the task first and send `ready` only from triage, todo,
  scheduled or blocked. Use the PATCH response instead of discarding it.
  `TasksStore.swift:227`, `:243`, `:276`. *reported*
- [ ] **Proceed needs an assignee.** A card block without one sends `""`, which unassigns; the
  dispatcher skips unassigned ready cards, so it shows "starting" forever. Require an assignee
  (picker from the existing `kanbanAssignees`). `TasksStore.swift:226`. *reported*
- [ ] **Proceed twice.** "Filed" lives in view state and `proceed` passes no idempotency key, so
  reopening the chat re-arms the button. Derive a key from the card. `EntityCardView.swift:92`,
  `TasksStore.swift:230`. *reported*

## Adopt next

Ideas taken from Conduit. Mostly reimplemented rather than copied, because Conduit's logic lives
in one 23k-line `AppState.swift`. Files named as "lifts" are standalone and MIT.

### Voice robustness

- [ ] Interruption, route-change, engine-configuration-change and media-services-reset observers
  in `SpeechRecognizer`. Today a call, Siri or AirPods connecting can stop the engine while the
  screen and Live Activity still say Listening. `BackgroundRecorder.swift:270-336` already has the
  pattern. *reported*
- [ ] A fresh `AVAudioEngine` per start, tap at the hardware format, one retry. Lifts:
  `Conduit/Voice/VoiceAudioEngineRecovery.swift` (110 lines).
- [ ] Playback-drain watchdog and a speak-stream idle timeout, so a silent socket cannot hold the
  state at Speaking. Handle `{"type":"error"}` frames. Conduit:
  `Conduit/Voice/AVSpeechPlaybackService.swift:219-244`, `HermesVoiceGateway.swift:255-285`.
- [ ] Strip emoji before speaking (about 25 lines from `Conduit/Voice/SpokenTextFilter.swift`).
- [ ] Optional experiment: barge-in on headsets only, by recognised words, using
  `Conduit/Voice/VoiceBargeInRoutePolicy.swift` (88 lines). Off by default.

### Session state

- [ ] Seed and clear `running` from `session.active_list` (only `working` and `waiting` count), on
  foreground and before a send, so a missed `message.complete` cannot leave a chat stuck.
- [ ] Recognise `SESSION_NOT_OWNED` (code 4090) and say the chat is open in another client, with
  the draft kept.
- [ ] Transcript projection: honour `display_kind` (`model_switch`, `personality_switch`,
  `auto_continue`, `async_delegation_complete`, `internal_notification`, `skill_invocation`) and
  hide compaction summaries, instead of rendering them as messages. `ChatStore.swift:580`.
- [ ] Re-resume on `status.update` with kind `compacted`.
- [ ] Stable row ids from `row_id`, and merge on resync, so attached images and scroll position
  survive. `ChatStore.swift:10`, `:147-158`.
- [ ] Use the `session.redirect` result (redirected, queued, otherwise rejected).
- [ ] Batch clarify: show every question, answer each with `clarify.lock`, allow free text beside
  choices.
- [ ] Later, if long chats are slow to open: `session.resume` with `omit_messages: true` plus
  `GET /api/sessions/{id}/messages?limit&offset&order=latest&include_compacted=true`.

### Notifications

- [ ] **Now:** local notifications for a pending approval or clarify and for a finished turn while
  the app is not active, tapping through to `talaria://chat/<id>`. This covers voice chat and
  recording, when the process is alive in the background.
- [ ] **With the developer account:** APNs without a relay. The app posts its device token to the
  `talaria` dashboard plugin over the tailnet; the plugin calls APNs with the .p8 key (server side
  in nix-config). This also allows Approve and Deny on the banner and push updates to the Live
  Activities. Because open requests are replayed on resume, the notification only has to open the
  chat.

### Chat

- [ ] Code blocks: language label and Copy. Tables: horizontal scroll. Per-reply Copy.
  All within MarkdownUI.
- [ ] Context meter from `session.info` (`context_percent`, `context_used`, `context_max`;
  the percent arrives as 0–1 or 0–100).
- [ ] Coalesce streaming deltas to about 30 Hz; today each delta re-parses the whole message.
- [ ] Cap expanded tool output (Conduit caps at 500 lines).
- [ ] Scrolling: bottom anchor, unanimated pin while following, interactive keyboard dismiss.
- [ ] `pdf.attach`; reasoning "off" in the model picker; accessibility labels on icon buttons.
- [ ] A "Start voice chat" App Shortcut for Siri, reusing `talaria://voice-chat`.

### Tasks

- [ ] Failure detail on the card: last failure, run history, parent titles for "waiting on".
  Tell `gave_up` and `block_loop_detected` apart from a real question (both show today as a
  question or as "Not started").
- [ ] Worker log tail: `GET /tasks/{id}/log?tail=`.
- [ ] Kanban live updates over `WS /api/plugins/kanban/events?ticket&board&since`, starting from
  the board's `latest_event_id`. Events only invalidate; REST stays the source of truth. Refresh
  the open card when its id appears. Conduit: `Conduit/Services/KanbanEventStream.swift`.
- [ ] Keep triage and board errors separate; show the create `warning` (dispatcher not running).

### Connection hygiene

- [ ] Allow plain HTTP only for local, RFC 1918 and Tailscale addresses, and clear cookies when
  the host changes. Lifts: `Conduit/Services/ConnectionURLPolicy.swift`.
- [ ] ATS: `NSAllowsArbitraryLoads` is ignored when `NSAllowsLocalNetworking` is present, so a
  `*.ts.net` name over HTTP would fail. Add exceptions for `ts.net` and `100.64.0.0/10` if a full
  tailnet name is ever used. Untested.

### Tests

- [ ] A `GatewaySocket` protocol in front of `URLSessionWebSocketTask` (about 25 lines) and a
  buffered fake socket.
- [ ] One Swift Testing target, hosted in the app, with recorded `.jsonl` frames as fixtures.
- [ ] First tests: seq gate and replay; frame routing and open-request redelivery; event-to-row
  reduction over a recorded turn; sentence splitting in `SpeechText`; card-block parsing.

## Not doing

Live voice providers, CarPlay, wake word, Conduit's Markdown renderer and scroll engine, OAuth,
Cloudflare Access, multiple dashboards, bot mode, xcodegen, CI, the dispatcher nudge
(`POST /dispatch` ignores the concurrency cap), third-party push services.
