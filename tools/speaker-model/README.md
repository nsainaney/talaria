# Speaker embedding model

`talaria/Voice/SpeakerEmbedding.mlpackage` is SpeechBrain's ECAPA-TDNN speaker model
([speechbrain/spkrec-ecapa-voxceleb](https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb),
Apache-2.0) converted to Core ML: 16 kHz mono float waveform in (1 × N, N one of the fixed lengths 1–20 s listed in
`convert.py`; the app crops to the largest that fits), 192-d embedding out. Run it with
`.cpuAndNeuralEngine`: the GPU path asserts on the enumerated shapes and crashes the process. Cosine similarity between embeddings says whether two utterances are the same voice; the app
enrols the owner once and drops utterances that do not match (TV, other people in the room).

Why it exists: Voice Isolation and loudness both failed on 2026-10-03 — TV dialogue is clean speech
and was louder at the phone than the person (mean level 0.34–0.39 vs 0.10).

## Rebuild

```sh
uv venv .venv -p 3.12
uv pip install -p .venv/bin/python torch torchaudio coremltools speechbrain soundfile numpy
.venv/bin/python convert.py        # writes SpeakerEmbedding.mlpackage, prints the checks
.venv/bin/python verify.py         # similarity matrix over voices/*.wav (make some with `say`)
```

`convert.py` rebuilds the Fbank front end from plain ops (DFT as a conv1d, mel matrix as a constant)
because SpeechBrain's own uses integer casts Core ML cannot convert, and patches
`length_to_mask` to all ones (one full-length utterance at a time). Checks printed on
2026-10-03: fbank max abs diff 0.0005 dB against SpeechBrain; embedding cosine 1.0 to the
SpeechBrain pipeline in PyTorch; Core ML (fp16) vs PyTorch cosine 0.988–0.99999 for 1–7 s inputs.

Four macOS `say` voices, two sentences each: same voice 0.73–0.79, different voices 0.06–0.36.
