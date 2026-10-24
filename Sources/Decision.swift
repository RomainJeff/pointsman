import Foundation

/// Pure decision helpers, kept free of AppKit so the self-test can compile them alone.
enum Decision {
    static let unsure = "none"

    /// Scheme + host + path only: query strings and fragments carry tokens (magic links, OAuth codes).
    static func redact(_ url: URL) -> String {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.query = nil
        c?.fragment = nil
        c?.user = nil
        c?.password = nil
        return c?.string ?? url.host ?? ""
    }

    /// Winning browser, or nil when the model picked "none", is below threshold, or named an unknown option.
    static func pick(_ probabilities: [String: Double], candidates: Set<String>, threshold: Double) -> String? {
        guard let best = probabilities.max(by: { $0.value < $1.value }),
              best.value >= threshold, candidates.contains(best.key) else { return nil }
        return best.key
    }
}
