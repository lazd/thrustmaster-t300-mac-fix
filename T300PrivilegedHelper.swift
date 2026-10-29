import Foundation
import IOKit

private let t300VendorID: UInt16 = 0x044f
private let genericProductID: UInt16 = 0xb65d
private let supportedProductID: UInt16 = 0xb66e
private let unsupportedProductIDs: Set<UInt16> = [0xb66d, 0xb66f]
private let allProductIDs: Set<UInt16> = [genericProductID, supportedProductID, 0xb66d, 0xb66f]

private struct HelperStatus: Encodable {
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
    guard let matching = IOServiceMatching("IOUSBDevice") else { return [] }
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
              allProductIDs.contains(productID) else {
            continue
        }
        products.insert(productID)
    }
    return products
}

@main
struct T300PrivilegedHelper {
    static func main() {
        guard CommandLine.arguments.count == 3 else {
            fputs("Usage: T300PrivilegedHelper <status-directory> <request-directory>\n", stderr)
            exit(2)
        }

        let stateDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let requestDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let statusURL = stateDirectory.appendingPathComponent("helper-state.json")
        let retryURL = requestDirectory.appendingPathComponent("initialize.request")
        let automaticInitializationDisabledURL = requestDirectory.appendingPathComponent("automatic-initialization.disabled")
        var lastState: String?
        var lastMessage: String?
        var attemptedForConnection = false

        func report(_ state: String, _ message: String) {
            guard state != lastState || message != lastMessage else { return }
            lastState = state
            lastMessage = message
            let status = HelperStatus(state: state, message: message)
            guard let data = try? JSONEncoder().encode(status) else { return }
            try? data.write(to: statusURL, options: .atomic)
        }

        while true {
            let products = connectedT300ProductIDs()
            if products.contains(genericProductID) {
                let retryRequested = FileManager.default.fileExists(atPath: retryURL.path)
                if retryRequested {
                    try? FileManager.default.removeItem(at: retryURL)
                    attemptedForConnection = false
                }

                let automaticInitializationEnabled = !FileManager.default.fileExists(atPath: automaticInitializationDisabledURL.path)
                if !attemptedForConnection && (retryRequested || automaticInitializationEnabled) {
                    attemptedForConnection = true
                    report("initializing", "Keep hands clear; the wheel may move.")
                    Thread.sleep(forTimeInterval: 3)
                    if !retryRequested && FileManager.default.fileExists(atPath: automaticInitializationDisabledURL.path) {
                        attemptedForConnection = false
                        report("waiting", "Automatic initialization is disabled")
                    } else if connectedT300ProductIDs().contains(genericProductID) {
                        var message = [CChar](repeating: 0, count: 1024)
                        let result = message.withUnsafeMutableBufferPointer { buffer in
                            t300_initialize(buffer.baseAddress, buffer.count)
                        }
                        let detail = message.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                        report(result > 0 ? "ready" : "error", detail.isEmpty ? "Initialization failed" : detail)
                    } else {
                        attemptedForConnection = false
                        report("waiting", "Waiting for T300")
                    }
                } else if !attemptedForConnection {
                    report("waiting", "Automatic initialization is disabled")
                }
            } else {
                attemptedForConnection = false
                if products.contains(supportedProductID) {
                    report("ready", "T300 is in PS3 / PC mode")
                } else if !products.isDisjoint(with: unsupportedProductIDs) {
                    report("unsupported", "Set the T300 switch to PS3 / PC and reconnect")
                } else {
                    report("waiting", "Waiting for T300")
                }
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}