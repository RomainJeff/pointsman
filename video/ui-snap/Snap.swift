import AppKit
import SwiftUI

@MainActor func snap(_ ctx: String, _ rules: [BrowserRule], _ out: String) {
    let router = Router()
    router.config.fallback = "com.apple.Safari"
    router.config.globalContext = ctx
    router.config.browsers = rules
    router.hasKey = true
    let host = NSHostingView(rootView: SettingsView(router: router))
    host.frame = NSRect(x: 0, y: 0, width: 580, height: 640)
    let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: .darkAqua)
    win.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])!.write(to: URL(fileURLWithPath: out))
}

@main struct Snap {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let dir = CommandLine.arguments[1]
        let c = "I'm a developer. Work links go in Chrome, personal browsing in Safari."
        let chrome = "Work: GitHub, Linear, Notion, Google Docs, anything signed in with my work account."
        let safari = "Personal: news, shopping, YouTube, banking."
        func ch(_ d: String) -> BrowserRule { BrowserRule(bundleId: "com.google.Chrome", name: "Google Chrome", description: d) }
        func sa(_ d: String) -> BrowserRule { BrowserRule(bundleId: "com.apple.Safari", name: "Safari", description: d) }
        // Typed two characters per frame; manifest lists the phase of each frame.
        func typed(_ t: String) -> [String] { stride(from: 2, to: t.count, by: 2).map { String(t.prefix($0)) } + [t] }
        var steps: [(String, String, [BrowserRule])] = [("start", "", [])]
        for p in typed(c) { steps.append(("ctx", p, [])) }
        steps.append(("chromeOn", c, [ch("")]))
        for p in typed(chrome) { steps.append(("chrome", c, [ch(p)])) }
        steps.append(("safariOn", c, [ch(chrome), sa("")]))
        for p in typed(safari) { steps.append(("safari", c, [ch(chrome), sa(p)])) }
        var manifest = ""
        for (i, s) in steps.enumerated() {
            snap(s.1, s.2, String(format: "%@/f%03d.jpg", dir, i))
            manifest += s.0 + "\n"
        }
        try! manifest.write(toFile: dir + "/manifest.txt", atomically: true, encoding: .utf8)
    }
}
