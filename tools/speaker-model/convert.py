"""ECAPA-TDNN speaker embedding, raw 16 kHz waveform in, Core ML out.

The Fbank front end is rebuilt from plain ops (DFT as a conv1d, mel matrix as a constant) so the
conversion has no data-dependent integer math; it is checked against speechbrain's own Fbank.
"""
import math
import numpy as np
import torch
import coremltools as ct
import speechbrain.lobes.models.ECAPA_TDNN as ecapa
from speechbrain.inference.speaker import EncoderClassifier

torch.set_grad_enabled(False)
ecapa.length_to_mask = lambda length, max_len=None, dtype=None, device=None: torch.ones(1, max_len)
enc = EncoderClassifier.from_hparams(source="speechbrain/spkrec-ecapa-voxceleb", savedir="pretrained", run_opts={"device": "cpu"})
enc.eval()
sb_fbank, emb = enc.mods.compute_features, enc.mods.embedding_model
fb = sb_fbank.compute_fbanks

N_FFT, WIN, HOP, N_MELS = 400, 400, 160, 80


class FrontEnd(torch.nn.Module):
    def __init__(self):
        super().__init__()
        n = torch.arange(WIN, dtype=torch.float64)
        window = torch.hamming_window(WIN, periodic=True, dtype=torch.float64)  # torch.stft default window shape in speechbrain
        k = torch.arange(N_FFT // 2 + 1, dtype=torch.float64)
        ang = 2 * math.pi * k[:, None] * n[None, :] / N_FFT
        basis = torch.cat([torch.cos(ang), -torch.sin(ang)], dim=0) * window  # (2*201, 400)
        self.register_buffer("basis", basis.float().unsqueeze(1))             # conv1d weight (402, 1, 400)
        n_freq = fb.all_freqs_mat.shape[1]
        f_central = fb.f_central.repeat(n_freq, 1).transpose(0, 1)
        band = fb.band.repeat(n_freq, 1).transpose(0, 1)
        mel = fb._create_fbank_matrix(f_central, band).float()                 # (201, 80)
        self.register_buffer("mel", mel)
        self.amin, self.ref, self.top_db = fb.amin, fb.ref_value, fb.top_db

    def forward(self, wav):                                   # (1, N)
        x = torch.nn.functional.pad(wav.unsqueeze(1), (N_FFT // 2, N_FFT // 2))  # center=True, constant
        spec = torch.nn.functional.conv1d(x, self.basis, stride=HOP)              # (1, 402, T)
        re, im = spec[:, : N_FFT // 2 + 1], spec[:, N_FFT // 2 + 1:]
        power = (re * re + im * im).transpose(1, 2)                               # (1, T, 201)
        fbanks = power @ self.mel                                                 # (1, T, 80)
        db = 10 * torch.log10(torch.clamp(fbanks, min=self.amin))
        db = db - 10 * math.log10(max(self.amin, self.ref))
        new_max = db.amax(dim=(1, 2), keepdim=True) - self.top_db
        return torch.maximum(db, new_max)


class Speaker(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.front = FrontEnd()

    def forward(self, wav):
        feats = self.front(wav)
        feats = feats - feats.mean(dim=1, keepdim=True)
        return emb(feats).squeeze(1)


def cos(a, b):
    a, b = np.asarray(a).ravel(), np.asarray(b).ravel()
    return float(a @ b / ((a @ a) ** 0.5 * (b @ b) ** 0.5))


front = FrontEnd().eval()
x = torch.randn(1, 16000 * 3)
mine, theirs = front(x), sb_fbank(x)
print("fbank shapes", tuple(mine.shape), tuple(theirs.shape), "max abs diff", (mine - theirs).abs().max().item())

model = Speaker().eval()
ref = model(x)
ref_sb = enc.encode_batch(x).squeeze()
print("embedding cosine to speechbrain pipeline", cos(ref, ref_sb))

traced = torch.jit.trace(model, x)
# Fixed lengths rather than a range: Core ML's GPU path asserts on dynamic shapes ("shape for
# TensorData is not static", crashed the app 2026-10-03) and the Neural Engine prefers static ones.
# The app crops an utterance down to the largest bucket that fits.
BUCKETS_S = [1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20]
shape = ct.EnumeratedShapes(shapes=[(1, int(16000 * b)) for b in BUCKETS_S], default=(1, 48000))
ml = ct.convert(traced, inputs=[ct.TensorType(name="wav", shape=shape, dtype=float)],
                outputs=[ct.TensorType(name="embedding")], minimum_deployment_target=ct.target.iOS17,
                compute_units=ct.ComputeUnit.CPU_AND_NE)
ml.short_description = "ECAPA-TDNN speaker embedding (speechbrain/spkrec-ecapa-voxceleb, Apache-2.0). 16 kHz mono float waveform in, 192-d embedding out."
ml.save("SpeakerEmbedding.mlpackage")
for secs in (1, 3, 8, 20):
    y = torch.randn(1, 16000 * secs)
    out = ml.predict({"wav": y.numpy()})["embedding"]
    print(f"{secs}s: coreml vs torch cosine", cos(out, model(y)))
