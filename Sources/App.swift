import SwiftUI

@main
struct PointsmanApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(router: delegate.router)
        } label: {
            Image(nsImage: menuBarIcon(icon))
        }
        // A plain Window, not Settings: openSettings is unreliable from a menu bar–only app.
        Window("Pointsman Settings", id: "settings") {
            SettingsView(router: delegate.router)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(CommandLine.arguments.contains("--settings") ? .presented : .suppressed)
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
    image.accessibilityDescription = "Pointsman"
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
        Text("Last: \(router.last)")
        Divider()
        Toggle("Smart routing", isOn: $router.config.enabled)
            .keyboardShortcut("e")
        if !router.config.browsers.isEmpty {
            Menu("Browsers offered to Jev") {
                ForEach($router.config.browsers, id: \.bundleId) { $b in
                    Toggle(b.name, isOn: $b.enabled)
                }
            }
        }
        Button("Settings…") { openSettings() }
            .keyboardShortcut(",")
        Button("Open log") { NSWorkspace.shared.open(Router.logURL) }
        Divider()
        Button("Quit Pointsman") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var status: String {
        let fallback = installedBrowsers().first { $0.id == router.config.fallback }?.name ?? router.config.fallback
        guard router.config.enabled else { return "Paused: everything goes to \(fallback)" }
        return "Active: \(router.config.browsers.filter(\.enabled).count) browser(s), fallback \(fallback)"
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// Palette of the Pointsman app icon: navy yard, cream rails, amber chosen route.
extension Color {
    static let navyTop = Color(hex: 0x22345C)
    static let navy = Color(hex: 0x0D1526)
    static let sleeper = Color(hex: 0x3A4E78)
    static let amber = Color(hex: 0xF5B43C)
    static let cream = Color(hex: 0xF3EBDD)

    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// Free text sits in a recessed well, darker than the row, so it reads as editable.
    func well() -> some View {
        textFieldStyle(.plain)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.navy.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.sleeper.opacity(0.6)))
    }
}

func appIcon(_ bundleId: String, size: CGFloat = 32) -> NSImage {
    let ws = NSWorkspace.shared
    let icon = ws.urlForApplication(withBundleIdentifier: bundleId).map { ws.icon(forFile: $0.path) }
        ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
    icon.size = NSSize(width: size, height: size)
    return icon
}

struct SettingsView: View {
    @Bindable var router: Router
    @State private var pane = Pane.browsers

    enum Pane: String, CaseIterable {
        case browsers = "Browsers", decision = "Decision", general = "General"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $pane) {
                ForEach(Pane.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 14)
            Group {
                switch pane {
                case .browsers: BrowsersPane(router: router)
                case .decision: DecisionPane(router: router)
                case .general: GeneralPane(router: router)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 580, height: 640)
        .background(LinearGradient(colors: [.navyTop, .navy], startPoint: .top, endPoint: .bottom))
        .tint(.amber)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "svg").flatMap(NSImage.init(contentsOf:)) {
                    Image(nsImage: icon).resizable().frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pointsman").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Every link goes to the browser it belongs in.")
                        .foregroundStyle(Color.cream.opacity(0.6))
                }
                Spacer()
                Toggle(router.config.enabled ? "Active" : "Paused", isOn: $router.config.enabled)
                    .toggleStyle(.switch)
            }
            .foregroundStyle(Color.cream)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 14)
            Sleepers().frame(height: 10)
        }
    }
}

/// The icon's sleepers, laid out as a horizontal track: used as the header's rule.
struct Sleepers: View {
    var body: some View {
        Canvas { ctx, size in
            let y = size.height / 2
            for x in stride(from: 4.0, to: size.width, by: 9) {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 3, height: size.height)), with: .color(.sleeper))
            }
            ctx.fill(Path(CGRect(x: 0, y: y - 1, width: size.width, height: 2)), with: .color(.cream.opacity(0.25)))
        }
    }
}

struct BrowsersPane: View {
    @Bindable var router: Router
    @State private var showOthers = false
    private let installed = installedBrowsers()

    var body: some View {
        let offered = installed.filter { rule(for: $0).wrappedValue.enabled }
        let others = installed.filter { !rule(for: $0).wrappedValue.enabled }
        Form {
            Section {
                TextField("Context", text: $router.config.globalContext,
                          prompt: Text("I'm a developer. Work tools go in Chrome, personal browsing in Safari."), axis: .vertical)
                    .lineLimit(3...6)
                    .well()
            } header: {
                Text("Your context")
            } footer: {
                Text("Sent to Jev with every link. Jev works best in English.")
            }
            Section {
                if offered.isEmpty {
                    Text("Enable at least one browser, or every link goes to the fallback.")
                        .foregroundStyle(.secondary)
                }
                ForEach(offered) { b in
                    BrowserRow(browser: b, rule: rule(for: b), isFallback: b.id == router.config.fallback)
                }
                DisclosureGroup("Other installed browsers (\(others.count))", isExpanded: $showOthers) {
                    ForEach(others) { b in
                        BrowserRow(browser: b, rule: rule(for: b), isFallback: b.id == router.config.fallback)
                    }
                }
            } header: {
                Text("Browsers offered to Jev")
            } footer: {
                Text("Describe when to pick each browser and when to avoid it. A removed browser keeps its description.")
            }
        }
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

struct BrowserRow: View {
    let browser: InstalledBrowser
    @Binding var rule: BrowserRule
    let isFallback: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $rule.enabled) {
                HStack(spacing: 10) {
                    Image(nsImage: appIcon(browser.id))
                    Text(browser.name).font(.headline)
                    if isFallback {
                        Text("Fallback")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(Capsule().stroke(Color.cream.opacity(0.4)))
                            .foregroundStyle(Color.cream.opacity(0.8))
                    }
                }
            }
            .toggleStyle(.switch)
            if rule.enabled {
                TextField("Description", text: $rule.description,
                          prompt: Text("Work: GitHub, Notion, Google Docs. Avoid for personal sites."), axis: .vertical)
                    .lineLimit(2...5)
                    .well()
                    .padding(.leading, 42)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DecisionPane: View {
    @Bindable var router: Router
    @State private var link = "https://github.com/acme/api/pull/42"
    @State private var opener = "Slack"
    @State private var probabilities: [String: Double] = [:]
    @State private var failure: String?
    @State private var asking = false
    private let installed = installedBrowsers()

    var body: some View {
        Form {
            Section {
                Picker("Fallback browser", selection: $router.config.fallback) {
                    ForEach(installed) { b in
                        Label { Text(b.name) } icon: { Image(nsImage: appIcon(b.id, size: 16)) }.tag(b.id)
                    }
                }
                LabeledContent("Minimum confidence") {
                    HStack {
                        Slider(value: $router.config.threshold, in: 0.3...0.95, step: 0.05).frame(width: 180)
                        Text("\(Int((router.config.threshold * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("When Jev is unsure")
            } footer: {
                Text("Below this threshold, or when no browser fits, the link goes to the fallback.")
            }
            Section {
                TextField("Link", text: $link)
                TextField("Clicked from", text: $opener)
                HStack {
                    if let failure { Text(failure).foregroundStyle(.red).lineLimit(2) }
                    Spacer()
                    if asking { ProgressView().controlSize(.small) }
                    Button("Test this link", action: test)
                        .keyboardShortcut(.defaultAction)
                        .disabled(asking || !router.hasKey || URL(string: link)?.host == nil)
                }
                if !probabilities.isEmpty { bench }
            } header: {
                Text("Test bench")
            } footer: {
                Text(router.hasKey
                     ? "Sends the link to Jev with your current settings. Nothing opens."
                     : "Add your OpenRouter key in General to test.")
            }
        }
    }

    /// One track per option; the vertical mark is the threshold and moves with the slider.
    private var bench: some View {
        let winner = Decision.pick(probabilities, candidates: Set(router.config.browsers.filter(\.enabled).map(\.bundleId)),
                                   threshold: router.config.threshold)
        let fallbackName = installed.first { $0.id == router.config.fallback }?.name ?? router.config.fallback
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(probabilities.sorted { $0.value > $1.value }, id: \.key) { id, p in
                HStack(spacing: 10) {
                    if id == Decision.unsure {
                        Image(systemName: "questionmark.circle").frame(width: 18)
                        Text("None").frame(width: 90, alignment: .leading)
                    } else {
                        Image(nsImage: appIcon(id, size: 18))
                        Text(router.config.browsers.first { $0.bundleId == id }?.name ?? id)
                            .frame(width: 90, alignment: .leading)
                            .lineLimit(1)
                    }
                    TrackBar(value: p, threshold: router.config.threshold, chosen: id == winner)
                    Text("\(Int((p * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            Text(winner.map { id in "This link would open in \(router.config.browsers.first { $0.bundleId == id }?.name ?? id)." }
                 ?? "Not sure enough: this link would open in \(fallbackName), the fallback.")
                .font(.callout.weight(.medium))
                .foregroundStyle(winner == nil ? Color.cream.opacity(0.7) : Color.amber)
                .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }

    private func test() {
        guard let url = URL(string: link) else { return }
        asking = true
        failure = nil
        Task {
            do { probabilities = try await router.ask(url, openerName: opener, openerId: "?") }
            catch { failure = error.localizedDescription; probabilities = [:] }
            asking = false
        }
    }
}

/// A probability drawn as a stretch of track: lit rail up to the value, amber with the link's dot when chosen.
struct TrackBar: View {
    let value: Double
    let threshold: Double
    let chosen: Bool

    var body: some View {
        Canvas { ctx, size in
            let y = size.height / 2
            for x in stride(from: 2.0, to: size.width, by: 7) {
                ctx.fill(Path(CGRect(x: x, y: y - 5, width: 2, height: 10)), with: .color(.sleeper))
            }
            func rail(to end: CGFloat, _ color: Color) {
                var p = Path()
                p.move(to: CGPoint(x: 2, y: y))
                p.addLine(to: CGPoint(x: end, y: y))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            rail(to: size.width - 2, .cream.opacity(0.12))
            let end = max(4, (size.width - 4) * value + 2)
            rail(to: end, chosen ? .amber : .cream.opacity(0.45))
            if chosen {
                ctx.fill(Path(ellipseIn: CGRect(x: end - 9, y: y - 9, width: 18, height: 18)), with: .color(.amber.opacity(0.3)))
                ctx.fill(Path(ellipseIn: CGRect(x: end - 4.5, y: y - 4.5, width: 9, height: 9)), with: .color(.cream))
            }
            let t = (size.width - 4) * threshold + 2
            ctx.fill(Path(CGRect(x: t - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(.cream.opacity(0.8)))
        }
        .frame(height: 20)
        .accessibilityLabel("\(Int(value * 100))%, threshold \(Int(threshold * 100))%")
    }
}

struct GeneralPane: View {
    @Bindable var router: Router
    @State private var apiKey = Keychain.get() ?? ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Default browser") {
                    if router.isDefault {
                        Label("Pointsman receives your links", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.cream.opacity(0.8))
                    } else {
                        Button("Make default") { router.makeDefault() }
                    }
                }
            } footer: {
                Text("To undo, pick another browser in System Settings > Desktop & Dock.")
            }
            Section {
                SecureField("API key", text: $apiKey, prompt: Text("sk-or-…"))
                    .onChange(of: apiKey) {
                        Keychain.set(apiKey)
                        router.hasKey = Router.apiKey != nil
                    }
                TextField("Model", text: $router.config.model)
            } header: {
                Text("OpenRouter")
            } footer: {
                Text("The key stays in the macOS Keychain. Jev gets the link's domain and path, never its parameters.")
            }
            Section {
                LabeledContent("Files") {
                    HStack {
                        Button("Decision log") { NSWorkspace.shared.open(Router.logURL) }
                        Button("Config file") { NSWorkspace.shared.activateFileViewerSelecting([Config.url]) }
                    }
                }
            }
        }
        .onAppear { router.refreshDefault() }
    }
}
