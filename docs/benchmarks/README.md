# Voice turn benchmark

How long a spoken question takes, stage by stage, so each change to the voice loop can be
measured against the one before. Started 2026-10-03.

## The questions

Benchmark, one lookup, two sentences to speak, a three-to-five sentence answer:

> What came in today, and what's the first one about?

Control, no tools, to separate the model's own latency from the lookup:

> What day is it tomorrow?

Ten runs of each, alternating, per configuration. Same phone, same room, same output route
(headset or speaker) for a whole series, screen on, Wi-Fi. Note the model in the pill and the
number of tool calls per run; a run with a different tool count took a different path and goes
in its own bucket.

## Measuring

The app writes one log line per stage to the `bench` category (`talaria/Voice/Bench.swift`):
`partial`, `utterance_end`, `submit`, `message_start`, `tool_start`/`tool_end`, `first_delta`,
`first_sentence`, `first_audio`, `message_complete`, `reply_end`. After a session:

    docs/benchmarks/voice-bench.py --collect Tyche --last 30m      # pulls the log (sudo) and prints the table
    docs/benchmarks/voice-bench.py tyche.logarchive --csv > results/<date>-<config>.csv

Columns, in seconds:

| column | from → to | what it is |
|---|---|---|
| `endpt` | last word → utterance sent | the pause the phone waits through |
| `start` | submit → `message.start` | Hermes taking the turn |
| `tools` | count × summed tool time | the lookups (server-reported durations) |
| `token` | `message.start` → first text | first token, includes the tools |
| `tts` | first sentence ready → first sound | synthesis to speaker |
| `hear` | last word → first sound | the silence you feel |
| `speak` | first sound → reply over | reply length |

Spoken approvals and clarify answers are excluded. Compare medians.

## Setup as of the baseline

- Hermes on prometheus: default model `glm-5.3-flash` on Ollama Cloud, `reasoning_effort: low`;
  aliases `coder` (`glm-5.3`) and `fast` (`gpt-oss:20b`), also hosted. All in nix-config
  `services/hermes.nix`.
- Context engine: SQLite FTS5 + sqlite-vec hybrid search; `context_triage` returns every waiting
  item (source, time, title, why, suggestion, id) in one call but no item text, so the benchmark
  question needs a second call for "what is it about".
- Talaria: end of utterance after 1.3 s without new words (2 s while Hermes works), up to two
  1 s extensions when the sentence trails off; server voice (Pocket TTS) one stream per sentence;
  voice model alias empty (so "fast model" only sets reasoning low, already the default).

## Experiments, in order

1. Baseline: the setup above, unchanged.
2. Voice alias `fast` (Settings → voice model alias). No code; compares `gpt-oss:20b` with
   `glm-5.3-flash`. Run the control too: a faster model that answers worse is not a win.
   **Result:** no gain. Model rounds unchanged (2.56 vs 2.49 s, 1.63 vs 1.54 s), replies nearly
   three times longer. Alias stays empty.
3. Endpoint pause, if `endpt` dominates: the constants in `VoiceController` (`endOfUtterance`,
   `unfinishedGrace`). Later, `SpeechAnalyzer` (iOS 26) to end on the recognizer's own finalized
   result instead of a timer.
   **Result (2be02d7, 1.3 → 0.8 s):** endpoint 1.37 → 0.85 s, `hear` 4.34 → 3.78 (benchmark) and
   3.21 → 2.87 (control), i.e. the whole half-second shows up in the wait; nothing else moved
   (model rounds 2.45/1.64 s, TTS 0.21 s). No early cut-offs in 20 turns. Kept. An earlier run
   that afternoon was discarded: the chat had answered the question before, so the model stopped
   calling the tool. The remaining `hear` is 65% model rounds and 23% endpoint, so the next
   halving would have to come from Hermes doing less per turn, not from the phone.
4. The phone's clock as the first line of `voice_context` ("Now on the phone: Saturday, October 3,
   2026 at 3:59 PM PDT"). Hermes 0.21.3's system prompt carries only the day the chat *started*
   and tells the model to "query tools for exact time", which is the `terminal` round seen in the
   smoke run. Hermes keeps `voice_context` out of the stored transcript, so this is model input
   only. Phone-side change in `ChatStore.VoiceTurn`; no server work. Expected effect: only on
   turns where the model would otherwise look the time up (first turn of a chat that is a day old,
   anything asking the hour), so the control medians should not move; the win is the absence of
   a 2–3 s outlier.
5. (dropped) A two-line excerpt per item in `context_triage`: the benchmark already takes one
   tool call at 0.02 s.
6. (dropped) First-clause speech and sentence pipelining in `HermesSpeaker`: TTS is 0.2 s warm.

## Seen along the way, to fix after the series

- 2026-10-03 smoke run: Pocket TTS stalled 41 s mid-reply on the second chunk (stream open, no
  audio frames, then finished). The phone has no per-stream stall timeout, so it waited. Fix:
  treat ~8 s without audio as a dropped stream (the per-sentence retry then re-synthesizes), and
  split chunks on newlines and bullets with a ~200-char cap so a retry repeats little. Check the
  pocket-tts container log on prometheus for the same minute to see which side stalled.
  Checked 2026-10-03: pocket-tts logged one `POST /tts` per stalled stream at its start and
  nothing until the retry; not queued, not CPU-throttled. The process had 364 MB of 930 MB in
  swap and 1.46 M major faults; the box had 15 GB swapped out with 1 GB free. Leading guess:
  idle torch pages swapped out between sessions, paged back mid-sentence. Try
  `memory.swap.max = 0` on the container (nix-config) and watch VmSwap on the PID during a stall.
- Pocket TTS clips the last syllable of a sentence ("…October 4th, 2026." loses the end of
  "twenty-six"); the audio from the container itself is already short, so neither Hermes nor the
  phone can restore it. `--frames-after-eos 8` on the CLI fixes it (picked by ear over
  `--eos-threshold -2` and 4 frames); the `/tts` route passes no EOS arguments, so nix-config
  70f73fc patches the call from the container entrypoint. Costs ~0.6 s of tail per sentence, which
  shifts `speak` and `reply_end` after the deploy.
- First TTS stream of a session takes ~2.5 s to first audio, later ones ~0.2 s: a warm-up request
  at voice start would hide it.
- The control question made the model run `terminal` to learn the date (a 2.7 s round) in the
  smoke run; never in the two fresh-chat series since. Experiment 4 puts the phone's clock in
  `voice_context`.

## Results

Medians. `results/<file>.csv` has the runs; the first four rows of the baseline file (before 13:37)
were the smoke run and are not counted. Baseline reading: model rounds 57% of the wait, the
endpoint pause 32%, TTS 5%. After experiment 3: model rounds 65%, endpoint 23%, TTS 6%.

Put each run's CSV in `results/` named `<date>-<config>.csv` and add a row here.

| date | config | n | endpt | start | tools | token | tts | hear | speak |
|---|---|---|---|---|---|---|---|---|---|
| 2026-10-03 | baseline, benchmark (1 tool) | 11 | 1.37 | 0.04 | 1× 0.02 | 2.49 | 0.18 | 4.34 | 8.93 |
| 2026-10-03 | baseline, control (no tool) | 9 | 1.36 | 0.04 | – | 1.54 | 0.20 | 3.21 | 2.57 |
| 2026-10-03 | alias `fast` (gpt-oss:20b), benchmark | 10 | 1.34 | 0.03 | 1× 0.02 | 2.56 | 0.22 | 4.42 | 24.47 |
| 2026-10-03 | alias `fast` (gpt-oss:20b), control | 10 | 1.37 | 0.04 | – | 1.63 | 0.26 | 3.44 | 3.44 |
| 2026-10-03 | endpoint 0.8 s (2be02d7), benchmark | 9 | 0.85 | 0.05 | 1× 0.02 | 2.45 | 0.21 | 3.78 | 15.98 |
| 2026-10-03 | endpoint 0.8 s (2be02d7), control | 9 | 0.84 | 0.06 | – | 1.64 | 0.23 | 2.87 | 3.05 |
