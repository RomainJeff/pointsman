import SwiftUI

@main
struct LinkRouterApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Link Router", systemImage: icon) {
            MenuContent(router: delegate.router)
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
        if !r.config.enabled { return "pause.circle" }
        return r.issues.isEmpty ? "arrow.triangle.branch" : "exclamationmark.triangle"
    }
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
        return "Actif : \(router.config.browsers.count) navigateur(s), repli \(fallback)"
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(b.name).bold()
                        TextField("Quand le choisir, quand l'éviter", text: description(for: b), axis: .vertical)
                    }
                }
            } header: {
                Text("Navigateurs")
            } footer: {
                Text("Description vide = jamais proposé au modèle. Écrire en anglais donne de meilleurs résultats avec Jev.")
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

    private func description(for b: InstalledBrowser) -> Binding<String> {
        Binding(
            get: { router.config.browsers.first { $0.bundleId == b.id }?.description ?? "" },
            set: { text in
                if let i = router.config.browsers.firstIndex(where: { $0.bundleId == b.id }) {
                    if text.isEmpty { router.config.browsers.remove(at: i) } else { router.config.browsers[i].description = text }
                } else if !text.isEmpty {
                    router.config.browsers.append(BrowserRule(bundleId: b.id, name: b.name, description: text))
                }
            })
    }
}
