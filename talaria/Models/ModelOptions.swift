import Foundation

/// The model picker payload from `model.options`: providers with their models and per-model capabilities.
struct ModelOptions {
    struct Provider: Identifiable {
        let slug: String
        let name: String
        let models: [String]
        let isCurrent: Bool
        let authenticated: Bool
        let warning: String?
        /// model → (fast, reasoning)
        let capabilities: [String: (fast: Bool, reasoning: Bool)]
        var id: String { slug }
    }

    let model: String
    let provider: String
    let providers: [Provider]

    init?(payload: [String: Any]) {
        guard let rows = payload["providers"] as? [[String: Any]] else { return nil }
        model = payload["model"] as? String ?? ""
        provider = payload["provider"] as? String ?? ""
        providers = rows.compactMap { r in
            guard let slug = r["slug"] as? String else { return nil }
            var caps: [String: (fast: Bool, reasoning: Bool)] = [:]
            for (m, c) in r["capabilities"] as? [String: [String: Any]] ?? [:] {
                caps[m] = (c["fast"] as? Bool ?? false, c["reasoning"] as? Bool ?? true)
            }
            return Provider(slug: slug, name: r["name"] as? String ?? slug, models: r["models"] as? [String] ?? [],
                            isCurrent: r["is_current"] as? Bool ?? false, authenticated: r["authenticated"] as? Bool ?? false,
                            warning: (r["warning"] as? String).flatMap { $0.isEmpty ? nil : $0 }, capabilities: caps)
        }
    }

    static let efforts: [(value: String, label: String)] = [
        ("minimal", "Minimal"), ("low", "Low"), ("medium", "Medium"), ("high", "High"),
        ("xhigh", "Extra High"), ("max", "Max"), ("ultra", "Ultra"),
    ]
}
