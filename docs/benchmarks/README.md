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
4. A two-line excerpt per item in `context_triage` (nix-config, `mcp_facade.py`), so the benchmark
   question is one tool call.
5. First-clause speech and sentence pipelining in `HermesSpeaker`, if `tts` dominates.

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
- First TTS stream of a session takes ~2.5 s to first audio, later ones ~0.2 s: a warm-up request
  at voice start would hide it.
- The control question made the model run `terminal` to learn the date (a 2.7 s round): put the
  date and time in `voice_context`.

## Results

Medians. `results/<file>.csv` has the runs; the first four rows of the baseline file (before 13:37)
were the smoke run and are not counted. Baseline reading: model rounds 57% of the wait, the
endpoint pause 32%, TTS 5%. Experiments 4 and 5 are dropped: the benchmark takes one tool call
(0.02 s) and TTS is 0.2 s warm.

Put each run's CSV in `results/` named `<date>-<config>.csv` and add a row here.

| date | config | n | endpt | start | tools | token | tts | hear | speak |
|---|---|---|---|---|---|---|---|---|---|
| 2026-10-03 | baseline, benchmark (1 tool) | 11 | 1.37 | 0.04 | 1× 0.02 | 2.49 | 0.18 | 4.34 | 8.93 |
| 2026-10-03 | baseline, control (no tool) | 9 | 1.36 | 0.04 | – | 1.54 | 0.20 | 3.21 | 2.57 |
| 2026-10-03 | alias `fast` (gpt-oss:20b), benchmark | 10 | 1.34 | 0.03 | 1× 0.02 | 2.56 | 0.22 | 4.42 | 24.47 |
| 2026-10-03 | alias `fast` (gpt-oss:20b), control | 10 | 1.37 | 0.04 | – | 1.63 | 0.26 | 3.44 | 3.44 |
