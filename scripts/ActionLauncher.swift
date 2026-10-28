import AppKit
import Foundation

@main
struct ActionLauncher {
    static func main() {
        let action = Bundle.main.object(forInfoDictionaryKey: "T300Action") as? String ?? "install"
        let scriptName = action == "uninstall" ? "uninstall.command" : "install.command"
        guard let scriptURL = Bundle.main.resourceURL?.appendingPathComponent(scriptName) else {
            fputs("Could not locate the bundled action script.\n", stderr)
            exit(1)
        }

        let terminal = Process()
        terminal.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        terminal.arguments = ["-a", "Terminal", scriptURL.path]
        do {
            try terminal.run()
        } catch {
            fputs("Could not open Terminal: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}