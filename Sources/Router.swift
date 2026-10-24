import AppKit
import Observation
import Security

struct BrowserRule: Codable, Hashable {
    var bundleId: String
    var name: String
    var description: String
}

/// Portable config: plain JSON in ~/.config, readable by a future Windows/Linux shim.
struct Config: Codable {
    var enabled = true
    var globalContext = ""
    var fallback = ""
    var model = "typesafe/jev-1.13"
    var threshold = 0.6
    var browsers: [BrowserRule] = []

    static let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/link-router/config.json")

    static func load() -> Config {
        (try? JSONDecoder().decode(Config.self, from: Data(contentsOf: url))) ?? Config()
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Self.url)
    }
}

struct InstalledBrowser: Identifiable {
    let id: String
    let name: String
}

/// Every app that can open https, minus ourselves (opening a link in ourselves would loop).
func installedBrowsers() -> [InstalledBrowser] {
    var seen = Set<String>()
    return NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!).compactMap { url in
        guard let id = Bundle(url: url)?.bundleIdentifier, id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
        return InstalledBrowser(id: id, name: url.deletingPathExtension().lastPathComponent)
    }.sorted { $0.name < $1.name }
}

enum Keychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "link-router",
        kSecAttrAccount as String: "openrouter",
    ]

    static func get() -> String? {
        var out: AnyObject?
        let q = base.merging([kSecReturnData as String: true]) { $1 }
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String) {
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return }
        SecItemAdd(base.merging([kSecValueData as String: Data(key.utf8)]) { $1 } as CFDictionary, nil)
    }
}

/// Jev via OpenRouter's decisions endpoint: one "choice" question, returns option → probability.
enum Jev {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func choose(state: String, options: [String: String], model: String, key: String) async throws -> [String: Double] {
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/alpha/decisions")!, timeoutInterval: 1.5)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "state": state,
            "questions": ["browser": [
                "type": "choice",
                "instructions": "The user clicked a link. Which browser should open it? Follow the user's context and each browser's description. Answer \"none\" if no browser clearly fits.",
                "criteria": options,
            ]],
            "provider": ["data_collection": "deny"],
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let answer = (json?["answers"] as? [String: Any])?["browser"] as? [String: Any]
        guard let probs = answer?["probabilities"] as? [String: Double] else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw Failure(errorDescription: "HTTP \(status): \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        return probs
    }
}

/// Process that sent the link. Helpers (Electron, XPC) resolve to their enclosing .app; CLIs keep their binary name.
struct Opener {
    let name: String
    let bundleId: String

    init(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier {
            name = app.localizedName ?? id
            bundleId = id
            return
        }
        var buf = [CChar](repeating: 0, count: 4096)
        let path = proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
        if let r = path.range(of: ".app/"), let b = Bundle(path: String(path[..<r.lowerBound]) + ".app"), let id = b.bundleIdentifier {
            name = b.infoDictionary?["CFBundleName"] as? String ?? id
            bundleId = id
        } else {
            name = path.isEmpty ? "unknown" : URL(fileURLWithPath: path).lastPathComponent
            bundleId = "?"
        }
    }
}

@MainActor
@Observable
final class Router {
    var config = Config.load() {
        didSet { config.save() }
    }
    var last = "Aucun lien routé"
    var hasKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] != nil || Keychain.get() != nil
    // ponytail: refreshed on launch, after makeDefault and per link; a change made in System Settings shows up on the next link
    var isDefault = false

    /// Setup gaps that make every link silently fall back; surfaced in the menu bar.
    var issues: [Issue] {
        var out: [Issue] = []
        if !isDefault { out.append(.notDefault) }
        if !hasKey { out.append(.noKey) }
        if config.browsers.isEmpty { out.append(.noBrowsers) }
        return out
    }

    enum Issue: String {
        case notDefault = "Pas navigateur par défaut"
        case noKey = "Clé OpenRouter manquante"
        case noBrowsers = "Aucun navigateur décrit"
    }

    static let logURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/LinkRouter/decisions.jsonl")

    init() {
        if config.fallback.isEmpty {
            config.fallback = Self.currentDefault() ?? "com.apple.Safari"
        }
        refreshDefault()
    }

    func refreshDefault() {
        let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        isDefault = app.flatMap { Bundle(url: $0)?.bundleIdentifier } == Bundle.main.bundleIdentifier
    }

    func open(_ url: URL, from opener: Opener) async {
        let start = Date()
        refreshDefault()
        let (target, reason) = await decide(url, opener: opener)
        let ws = NSWorkspace.shared
        if let app = ws.urlForApplication(withBundleIdentifier: target) ?? ws.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            ws.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        let name = config.browsers.first { $0.bundleId == target }?.name ?? target
        last = "\(url.host ?? "?") → \(name) (\(reason), \(ms) ms)"
        log(["at": ISO8601DateFormatter().string(from: start), "opener": "\(opener.name) (\(opener.bundleId))",
             "url": Decision.redact(url), "target": target, "reason": reason, "ms": ms])
    }

    private func decide(_ url: URL, opener: Opener) async -> (String, String) {
        let c = config
        guard c.enabled else { return (c.fallback, "désactivé") }
        // ponytail: local URLs (OAuth callbacks from CLIs, dev servers) never go to the model
        guard let host = url.host, !["localhost", "127.0.0.1", "::1"].contains(host) else { return (c.fallback, "local") }
        guard !c.browsers.isEmpty else { return (c.fallback, "aucun candidat") }
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? Keychain.get() else { return (c.fallback, "pas de clé") }

        let state = """
        User context: \(c.globalContext.isEmpty ? "(none)" : c.globalContext)
        Link clicked in app: \(opener.name) (\(opener.bundleId))
        URL: \(Decision.redact(url))
        """
        var options = Dictionary(uniqueKeysWithValues: c.browsers.map { ($0.bundleId, "\($0.name): \($0.description)") })
        options[Decision.unsure] = "No browser clearly fits this link"
        do {
            let probs = try await Jev.choose(state: state, options: options, model: c.model, key: key)
            let top = probs.max { $0.value < $1.value }.map { "\(Int($0.value * 100)) %" } ?? "?"
            guard let id = Decision.pick(probs, candidates: Set(c.browsers.map(\.bundleId)), threshold: c.threshold) else {
                return (c.fallback, "incertain \(top)")
            }
            return (id, "jev \(top)")
        } catch {
            return (c.fallback, "erreur: \(error.localizedDescription)")
        }
    }

    func makeDefault() {
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme) { _ in
                Task { @MainActor in self.refreshDefault() }
            }
        }
    }

    private static func currentDefault() -> String? {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
              let id = Bundle(url: app)?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
        return id
    }

    private func log(_ entry: [String: Any]) {
        guard let line = try? JSONSerialization.data(withJSONObject: entry, options: .sortedKeys) else { return }
        try? FileManager.default.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: Self.logURL) {
            h.seekToEndOfFile()
            h.write(line + Data("\n".utf8))
            try? h.close()
        } else {
            try? (line + Data("\n".utf8)).write(to: Self.logURL)
        }
    }
}
