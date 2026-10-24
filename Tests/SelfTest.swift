import Foundation

@main
struct SelfTest {
    static func main() {
        let url = URL(string: "https://user:pw@accounts.example.com/magic/login?token=SECRET#frag")!
        assert(Decision.redact(url) == "https://accounts.example.com/magic/login")

        let candidates: Set = ["com.google.Chrome", "company.thebrowser.Browser"]
        assert(Decision.pick(["com.google.Chrome": 0.8, "none": 0.2], candidates: candidates, threshold: 0.6) == "com.google.Chrome")
        assert(Decision.pick(["com.google.Chrome": 0.5, "none": 0.5], candidates: candidates, threshold: 0.6) == nil)
        assert(Decision.pick(["none": 0.9, "com.google.Chrome": 0.1], candidates: candidates, threshold: 0.6) == nil)
        assert(Decision.pick(["org.mozilla.firefox": 0.9], candidates: candidates, threshold: 0.6) == nil)
        assert(Decision.pick([:], candidates: candidates, threshold: 0.6) == nil)
        print("selftest ok")
    }
}
