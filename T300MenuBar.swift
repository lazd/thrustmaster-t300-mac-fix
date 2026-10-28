import AppKit
import IOKit

private let t300VendorID: UInt16 = 0x044f
private let genericProductID: UInt16 = 0xb65d
private let supportedProductID: UInt16 = 0xb66e
private let unsupportedProductIDs: Set<UInt16> = [0xb66d, 0xb66f]
private let allT300ProductIDs: Set<UInt16> = [genericProductID, supportedProductID, 0xb66d, 0xb66f]

private struct InitializationResult {
    let succeeded: Bool
    let message: String
}

private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func appleScriptQuoted(_ value: String) -> String {
    "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

private func runInitializer(projectDirectory: String, nodePath: String) -> InitializationResult {
    let scriptPath = URL(fileURLWithPath: projectDirectory)
        .appendingPathComponent("initialize-t300.mjs").path
    let command = "cd \(shellQuoted(projectDirectory)) && \(shellQuoted(nodePath)) \(shellQuoted(scriptPath)) --initialize"
    let appleScript = "do shell script \(appleScriptQuoted(command)) with administrator privileges"
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", appleScript]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return InitializationResult(succeeded: false, message: error.localizedDescription)
    }

    let output = String(
        decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    )
    let errorOutput = String(
        decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    )
    let succeeded = process.terminationStatus == 0 &&
        (output.contains("Initialization successful") || output.contains("already in PS3 / PC USB mode"))
    let detail = (errorOutput.isEmpty ? output : errorOutput)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return InitializationResult(
        succeeded: succeeded,
        message: succeeded ? "Initialized successfully" : (detail.isEmpty ? "Initialization failed" : detail)
    )
}

private func readUSBNumber(_ service: io_service_t, key: String) -> UInt16? {
    guard let property = IORegistryEntryCreateCFProperty(
        service,
        key as CFString,
        kCFAllocatorDefault,
        0
    ) else {
        return nil
    }
    return (property.takeRetainedValue() as? NSNumber)?.uint16Value
}

private func connectedT300ProductIDs() -> Set<UInt16> {
    guard let matching = IOServiceMatching("IOUSBHostDevice") else { return [] }
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
        return []
    }
    defer { IOObjectRelease(iterator) }

    var products = Set<UInt16>()
    while true {
        let service = IOIteratorNext(iterator)
        if service == IO_OBJECT_NULL { break }
        defer { IOObjectRelease(service) }

        guard readUSBNumber(service, key: "idVendor") == t300VendorID,
              let productID = readUSBNumber(service, key: "idProduct"),
              allT300ProductIDs.contains(productID) else {
            continue
        }
        products.insert(productID)
    }
    return products
}

@MainActor
private final class T300MenuBarDelegate: NSObject, NSApplicationDelegate {
    private let projectDirectory: String
    private let nodePath: String
    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var initializeItem: NSMenuItem!
    private var timer: Timer?
    private var productIDs = Set<UInt16>()
    private var isInitializing = false
    private var attemptedThisConnection = false
    private var initializationSucceeded = false
    private var initializationError: String?

    init(projectDirectory: String, nodePath: String) {
        self.projectDirectory = projectDirectory
        self.nodePath = nodePath
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        stateItem = NSMenuItem(title: "Waiting for T300", action: nil, keyEquivalent: "")
        menu.addItem(stateItem)
        menu.addItem(.separator())

        initializeItem = NSMenuItem(title: "Initialize Now", action: #selector(initializeFromMenu), keyEquivalent: "")
        initializeItem.target = self
        menu.addItem(initializeItem)

        let quitItem = NSMenuItem(title: "Quit T300 Mac Fix", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.menu = menu
        statusItem.button?.image = NSImage(
            systemSymbolName: "steeringwheel",
            accessibilityDescription: "Thrustmaster T300"
        )
        statusItem.button?.toolTip = "Thrustmaster T300"
        statusItem.isVisible = false

        timer = Timer.scheduledTimer(
            timeInterval: 1.5,
            target: self,
            selector: #selector(refreshDevices),
            userInfo: nil,
            repeats: true
        )
        refreshDevices()
    }

    @objc private func refreshDevices() {
        productIDs = connectedT300ProductIDs()
        statusItem.isVisible = !productIDs.isEmpty

        if productIDs.isEmpty {
            if !isInitializing {
                attemptedThisConnection = false
                initializationSucceeded = false
                initializationError = nil
            }
            stateItem.title = isInitializing ? "🔄 Initializing T300…" : "Waiting for T300"
            initializeItem.isEnabled = false
            return
        }

        if productIDs.contains(supportedProductID) {
            stateItem.title = initializationSucceeded
                ? "✅ Initialized successfully"
                : "✅ T300 ready · PS3 / PC mode"
        } else if productIDs.contains(genericProductID) {
            if isInitializing {
                stateItem.title = "🔐 Authorizing and initializing…"
            } else if let initializationError {
                stateItem.title = "❌ \(initializationError)"
            } else {
                stateItem.title = "⚠️ Initialization needed"
            }
        } else if !productIDs.isDisjoint(with: unsupportedProductIDs) {
            stateItem.title = "⚠️ Unsupported mode · set switch to PS3 / PC"
        }

        initializeItem.title = initializationError == nil ? "Initialize Now" : "Retry Initialization"
        initializeItem.isEnabled = productIDs.contains(genericProductID) && !isInitializing

        if productIDs.contains(genericProductID), !isInitializing, !attemptedThisConnection {
            attemptedThisConnection = true
            startInitialization()
        }
    }

    @objc private func initializeFromMenu() {
        guard productIDs.contains(genericProductID), !isInitializing else { return }
        attemptedThisConnection = true
        initializationError = nil
        startInitialization()
    }

    private func startInitialization() {
        isInitializing = true
        initializationSucceeded = false
        stateItem.title = "🔐 Authorizing and initializing…"
        initializeItem.isEnabled = false

        let projectDirectory = projectDirectory
        let nodePath = nodePath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runInitializer(projectDirectory: projectDirectory, nodePath: nodePath)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isInitializing = false
                self.initializationSucceeded = result.succeeded
                self.initializationError = result.succeeded ? nil : result.message
                self.refreshDevices()
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@main
struct T300MenuBarApp {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count >= 3 else {
            fputs("Usage: T300MenuBar <project-directory> <node-path>\n", stderr)
            return
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = T300MenuBarDelegate(
            projectDirectory: CommandLine.arguments[1],
            nodePath: CommandLine.arguments[2]
        )
        application.delegate = delegate
        application.run()
    }
}