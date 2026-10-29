import AppKit
import IOKit

private let t300VendorID: UInt16 = 0x044f
private let genericProductID: UInt16 = 0xb65d
private let supportedProductID: UInt16 = 0xb66e
private let unsupportedProductIDs: Set<UInt16> = [0xb66d, 0xb66f]
private let allT300ProductIDs: Set<UInt16> = [genericProductID, supportedProductID, 0xb66d, 0xb66f]

private struct HelperStatus: Decodable {
    let state: String
    let message: String
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
    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var initializeItem: NSMenuItem!
    private var automaticInitializationItem: NSMenuItem!
    private var timer: Timer?
    private var productIDs = Set<UInt16>()
    private var helperStatus: HelperStatus?
    private var manualInitializationPending = false
    private let stateDirectory = URL(fileURLWithPath: "/Library/Application Support/T300 Mac Fix", isDirectory: true)
    private let requestDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/T300 Mac Fix", isDirectory: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        stateItem = NSMenuItem(title: "Waiting for T300", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        initializeItem = NSMenuItem(title: "Initialize Now", action: #selector(initializeFromMenu), keyEquivalent: "")
        initializeItem.target = self
        menu.addItem(initializeItem)
        menu.addItem(.separator())

        automaticInitializationItem = NSMenuItem(
            title: "Initialize automatically when connected",
            action: #selector(toggleAutomaticInitialization),
            keyEquivalent: ""
        )
        automaticInitializationItem.target = self
        automaticInitializationItem.isEnabled = true
        automaticInitializationItem.state = FileManager.default.fileExists(
            atPath: requestDirectory.appendingPathComponent("automatic-initialization.disabled").path
        ) ? .off : .on
        menu.addItem(automaticInitializationItem)
        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(title: "Uninstall T300 Mac Fix...", action: #selector(uninstallFromMenu), keyEquivalent: "")
        uninstallItem.target = self
        uninstallItem.isEnabled = true
        menu.addItem(uninstallItem)

        let quitItem = NSMenuItem(title: "Quit T300 Mac Fix", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
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
        helperStatus = readHelperStatus()
        if helperStatus?.state == "initializing" {
            manualInitializationPending = false
        }
        statusItem.isVisible = !productIDs.isEmpty

        if productIDs.isEmpty {
            stateItem.title = "Waiting for T300"
            initializeItem.isEnabled = false
            return
        }

        if productIDs.contains(supportedProductID) {
            stateItem.title = helperStatus?.state == "ready"
                ? "✅ Initialized successfully"
                : "✅ T300 ready · PS3 / PC mode"
        } else if productIDs.contains(genericProductID) {
            if manualInitializationPending || helperStatus?.state == "initializing" {
                stateItem.title = "⏳ Initializing"
            } else {
                switch helperStatus?.state {
                case "error":
                    stateItem.title = "❌ \(helperStatus?.message ?? "Initialization failed")"
                case "ready":
                    stateItem.title = "✅ T300 initialized"
                case "unsupported":
                    stateItem.title = "⚠️ \(helperStatus?.message ?? "Unsupported mode")"
                case "waiting":
                    stateItem.title = "⚠️ Initialization needed"
                default:
                    stateItem.title = "❌ Privileged helper is not running"
                }
            }
        } else if !productIDs.isDisjoint(with: unsupportedProductIDs) {
            stateItem.title = "⚠️ Unsupported mode · set switch to PS3 / PC"
        }

        let alreadyInitialized = productIDs.contains(supportedProductID) || helperStatus?.state == "ready"
        initializeItem.isEnabled = productIDs.contains(genericProductID) &&
            !alreadyInitialized && !manualInitializationPending &&
            helperStatus != nil && helperStatus?.state != "initializing"
    }

    @objc private func initializeFromMenu() {
                guard productIDs.contains(genericProductID),
                            !productIDs.contains(supportedProductID),
                            helperStatus?.state != "ready",
                            helperStatus?.state != "initializing" else { return }
        let requestURL = requestDirectory.appendingPathComponent("initialize.request")
        do {
            try FileManager.default.createDirectory(at: requestDirectory, withIntermediateDirectories: true)
            try Data().write(to: requestURL, options: .atomic)
                        manualInitializationPending = true
                        stateItem.title = "⏳ Initializing"
            initializeItem.isEnabled = false
        } catch {
            stateItem.title = "❌ Could not contact privileged helper"
        }
    }

    @objc private func toggleAutomaticInitialization() {
        let disabledURL = requestDirectory.appendingPathComponent("automatic-initialization.disabled")
        do {
            if FileManager.default.fileExists(atPath: disabledURL.path) {
                try FileManager.default.removeItem(at: disabledURL)
                automaticInitializationItem.state = .on
            } else {
                try FileManager.default.createDirectory(at: requestDirectory, withIntermediateDirectories: true)
                try Data().write(to: disabledURL, options: .atomic)
                automaticInitializationItem.state = .off
            }
        } catch {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Could not change automatic initialization"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func readHelperStatus() -> HelperStatus? {
        let statusURL = stateDirectory.appendingPathComponent("helper-state.json")
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return try? JSONDecoder().decode(HelperStatus.self, from: data)
    }

    @objc private func uninstallFromMenu() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "Uninstall T300 Mac Fix?"
        confirmation.informativeText = "This will remove the app, privileged helper, and startup services. Terminal will open and ask for administrator approval."
        confirmation.addButton(withTitle: "Cancel")
        confirmation.addButton(withTitle: "Uninstall")
        guard confirmation.runModal() == .alertSecondButtonReturn else { return }

        do {
            guard let scriptURL = Bundle.main.url(forResource: "uninstall", withExtension: "command"),
                  let rootScriptURL = Bundle.main.url(forResource: "uninstall-root", withExtension: "sh"),
                  FileManager.default.fileExists(atPath: rootScriptURL.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let terminal = Process()
            terminal.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            terminal.arguments = ["-a", "Terminal", scriptURL.path]
            try terminal.run()
            terminal.waitUntilExit()
            guard terminal.terminationStatus == 0 else {
                throw CocoaError(.executableLoad)
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Could not start uninstallation"
            alert.informativeText = error.localizedDescription
            alert.runModal()
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
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = T300MenuBarDelegate()
        application.delegate = delegate
        application.run()
    }
}