import CoreML
import Foundation
import os

/// Fixed-length history of mono samples; the newest `count` are kept, older ones fall off.
struct AudioRing {
    private var samples: [Float]
    private var head = 0
    private var filled = 0

    init(seconds: Double, sampleRate: Int = 16000) {
        samples = [Float](repeating: 0, count: Int(seconds * Double(sampleRate)))
    }

    mutating func append(_ new: [Float]) {
        for s in new {
            samples[head] = s
            head = (head + 1) % samples.count
        }
        filled = min(samples.count, filled + new.count)
    }

    mutating func clear() { head = 0; filled = 0 }

    /// The newest `n` samples (fewer if the ring has not filled that far), oldest first.
    func last(_ n: Int) -> [Float] {
        let n = min(n, filled)
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        var i = (head - n + samples.count) % samples.count
        for k in 0..<n {
            out[k] = samples[i]
            i = (i + 1) % samples.count
        }
        return out
    }
}

/// Says whether a stretch of speech is the phone's owner. Each utterance becomes a 192-d voice
/// embedding (ECAPA-TDNN, on the Neural Engine, see tools/speaker-model) and is compared by cosine
/// to the profile enrolled in Settings. Loudness and Voice Isolation both failed at this: TV
/// dialogue is clean speech, often louder at the phone than the person.
actor SpeakerVerifier {
    static let shared = SpeakerVerifier()
    private static let profileKey = "talaria.voiceProfile"
    private static let log = Logger(subsystem: "com.sainaney.talaria", category: "voice")

    /// Same-voice pairs scored 0.73–0.79 and different voices 0.06–0.36 on synthetic speech; real
    /// room audio with a TV underneath scores lower, so the bar sits well under the same-voice band.
    /// Every utterance's score goes to the bench log so this can be tuned from device data.
    static let threshold: Float = 0.45
    /// Input lengths the model was compiled for (see tools/speaker-model/convert.py); an utterance
    /// is cropped to the largest that fits. Shorter than the first and the embedding is noise.
    static let bucketSeconds: [Double] = [1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20]
    static let minimumSeconds = bucketSeconds[0]

    private var model: SpeakerEmbedding?
    private var profile: [Float]?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.profileKey), data.count == 192 * 4 {
            profile = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
    }

    nonisolated static var hasProfile: Bool { UserDefaults.standard.data(forKey: profileKey) != nil }

    var isEnrolled: Bool { profile != nil }

    /// Load the model and run one prediction so the first real utterance does not pay for the
    /// Neural Engine compile (tens of seconds after a fresh install).
    func warmUp() {
        let t = Date()
        _ = try? embedding([Float](repeating: 0, count: 16000 * 2))
        Self.log.info("speaker model warm in \(Date().timeIntervalSince(t), format: .fixed(precision: 2)) s")
    }

    /// Unit-length embedding of 16 kHz mono samples; nil when there is too little audio.
    func embedding(_ samples: [Float]) throws -> [Float]? {
        guard let bucket = Self.bucketSeconds.last(where: { Int($0 * 16000) <= samples.count }) else { return nil }
        let samples = Array(samples.prefix(Int(bucket * 16000)))
        if model == nil {
            let config = MLModelConfiguration()
            // Not the GPU: its graph runtime asserts on this model's set of input lengths and takes
            // the app down with it (2026-10-03).
            config.computeUnits = .cpuAndNeuralEngine
            model = try SpeakerEmbedding(configuration: config)
        }
        guard let model else { return nil }
        let input = try MLMultiArray(shape: [1, NSNumber(value: samples.count)], dataType: .float32)
        samples.withUnsafeBufferPointer { src in
            input.dataPointer.withMemoryRebound(to: Float.self, capacity: samples.count) { dst in
                dst.update(from: src.baseAddress!, count: samples.count)
            }
        }
        let out = try model.prediction(wav: input).embedding
        var e = (0..<out.count).map { out[$0].floatValue }
        let norm = max(sqrt(e.reduce(0) { $0 + $1 * $1 }), 1e-6)
        for i in e.indices { e[i] /= norm }
        return e
    }

    /// Cosine similarity of these samples to the enrolled voice; nil when nothing is enrolled or
    /// the audio is too short.
    func similarity(_ samples: [Float]) -> Float? {
        guard let profile else { return nil }
        do {
            guard let e = try embedding(samples) else { return nil }
            return zip(e, profile).reduce(0) { $0 + $1.0 * $1.1 }
        } catch {
            Self.log.error("speaker embedding failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Average the embeddings of several enrolment recordings into the profile. Returns the
    /// pairwise agreement between them (low means the recordings disagree: noise, or not one voice).
    func enroll(_ recordings: [[Float]]) throws -> Float {
        let embeddings = try recordings.compactMap { try embedding($0) }
        guard embeddings.count >= 2 else { throw EnrollError.tooShort }
        var mean = [Float](repeating: 0, count: 192)
        for e in embeddings { for i in e.indices { mean[i] += e[i] } }
        let norm = max(sqrt(mean.reduce(0) { $0 + $1 * $1 }), 1e-6)
        for i in mean.indices { mean[i] /= norm }
        var agreement: Float = 0, pairs: Float = 0
        for i in embeddings.indices {
            for j in embeddings.indices where j > i {
                agreement += zip(embeddings[i], embeddings[j]).reduce(0) { $0 + $1.0 * $1.1 }
                pairs += 1
            }
        }
        agreement /= max(pairs, 1)
        profile = mean
        UserDefaults.standard.set(mean.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: Self.profileKey)
        Self.log.notice("voice profile enrolled from \(embeddings.count) recordings, agreement \(agreement)")
        return agreement
    }

    func forget() {
        profile = nil
        UserDefaults.standard.removeObject(forKey: Self.profileKey)
    }

    enum EnrollError: LocalizedError {
        case tooShort
        var errorDescription: String? { "At least two recordings of a second or more are needed." }
    }
}
