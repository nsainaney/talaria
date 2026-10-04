import glob, time, numpy as np, soundfile as sf, coremltools as ct
ml = ct.models.MLModel("SpeakerEmbedding.mlpackage")
def emb(path):
    w, sr = sf.read(path, dtype="float32"); assert sr == 16000
    if w.ndim > 1: w = w.mean(1)
    t = time.perf_counter(); e = ml.predict({"wav": w[None, :]})["embedding"].ravel(); dt = time.perf_counter() - t
    return e / np.linalg.norm(e), dt, len(w) / 16000
files = sorted(glob.glob("voices/*.wav")); E = {}
for f in files:
    e, dt, secs = emb(f); E[f] = e; print(f"{f:28s} {secs:4.1f}s audio, {dt*1000:5.0f} ms")
names = [f.split("/")[-1][:-4] for f in files]
print("\n" + " " * 12 + "".join(f"{n[:10]:>11s}" for n in names))
for f, n in zip(files, names):
    print(f"{n[:10]:>11s} " + "".join(f"{float(E[f] @ E[g]):11.2f}" for g in files))
