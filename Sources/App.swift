import SwiftUI

@main
struct LinkRouterApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(router: delegate.router)
        } label: {
            Image(nsImage: menuBarIcon(icon))
        }
        // A plain Window, not Settings: openSettings is unreliable from a menu bar–only app.
        Window("Réglages Link Router", id: "settings") {
            SettingsView(router: delegate.router)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }

    private var icon: String {
        let r = delegate.router
        if !r.config.enabled { return "menubar-paused" }
        return r.issues.isEmpty ? "menubar-active" : "menubar-warning"
    }
}

/// Template image: macOS tints it for light/dark menu bars. Note: NSImage's SVG renderer ignores per-path stroke-opacity, use opacity.
private func menuBarIcon(_ name: String) -> NSImage {
    let image = Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        ?? NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)!
    image.isTemplate = true
    image.accessibilityDescription = "Link Router"
    return image
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let router = Router()

    // Must be registered before launch finishes: the URL that launched us arrives right after.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s) else { return }
        let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value ?? 0
        let opener = Opener(pid: pid)
        Task { await router.open(url, from: opener) }
    }
}

struct MenuContent: View {
    @Bindable var router: Router
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(status)
        ForEach(router.issues, id: \.self) { issue in
            Button("⚠︎ \(issue.rawValue)") {
                issue == .notDefault ? router.makeDefault() : openSettings()
            }
        }
        Text("Dernier : \(router.last)")
        Divider()
        Toggle("Routage intelligent", isOn: $router.config.enabled)
            .keyboardShortcut("e")
        if !router.config.browsers.isEmpty {
            Menu("Navigateurs proposés à Jev") {
                ForEach($router.config.browsers, id: \.bundleId) { $b in
                    Toggle(b.name, isOn: $b.enabled)
                }
            }
        }
        Button("Réglages…") { openSettings() }
            .keyboardShortcut(",")
        Button("Ouvrir le journal") { NSWorkspace.shared.open(Router.logURL) }
        Divider()
        Button("Quitter") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var status: String {
        let fallback = installedBrowsers().first { $0.id == router.config.fallback }?.name ?? router.config.fallback
        guard router.config.enabled else { return "En pause : tout va vers \(fallback)" }
        return "Actif : \(router.config.browsers.filter(\.enabled).count) navigateur(s), repli \(fallback)"
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @Bindable var router: Router
    @State private var apiKey = Keychain.get() ?? ""
    private let installed = installedBrowsers()

    var body: some View {
        Form {
            Section("Contexte global") {
                TextEditor(text: $router.config.globalContext)
                    .frame(height: 70)
            }
            Section {
                ForEach(installed) { b in
                    let r = rule(for: b)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: r.enabled) { Text(b.name).bold() }
                        TextField("Quand le choisir, quand l'éviter", text: r.description, axis: .vertical)
                            .disabled(!r.wrappedValue.enabled)
                    }
                }
            } header: {
                Text("Navigateurs")
            } footer: {
                Text("Seuls les navigateurs activés sont proposés à Jev ; la description est gardée quand tu désactives. Écrire en anglais donne de meilleurs résultats.")
            }
            Section("Repli") {
                Picker("Navigateur par défaut", selection: $router.config.fallback) {
                    ForEach(installed) { Text($0.name).tag($0.id) }
                }
                Slider(value: $router.config.threshold, in: 0.3...0.95, step: 0.05) {
                    Text("Seuil de confiance : \(Int(router.config.threshold * 100)) %")
                }
            }
            Section("Modèle (OpenRouter)") {
                TextField("Modèle", text: $router.config.model)
                SecureField("Clé OpenRouter (stockée dans le Trousseau)", text: $apiKey)
                    .onChange(of: apiKey) {
                        Keychain.set(apiKey)
                        router.hasKey = !apiKey.isEmpty
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 680)
    }

    /// Rules exist only for browsers that are enabled or described, so the JSON stays short.
    private func rule(for b: InstalledBrowser) -> Binding<BrowserRule> {
        Binding(
            get: { router.config.browsers.first { $0.bundleId == b.id } ?? BrowserRule(bundleId: b.id, name: b.name, description: "", enabled: false) },
            set: { new in
                let keep = new.enabled || !new.description.isEmpty
                switch (router.config.browsers.firstIndex { $0.bundleId == b.id }, keep) {
                case let (i?, true): router.config.browsers[i] = new
                case let (i?, false): router.config.browsers.remove(at: i)
                case (nil, true): router.config.browsers.append(new)
                case (nil, false): break
                }
            })
    }
}
