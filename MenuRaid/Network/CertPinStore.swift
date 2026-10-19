import Foundation

/// Pinned certificate fingerprints (SHA-256 of the leaf certificate, hex with colons), keyed by host.
/// Trust on first use: a pin is only stored after the user confirms the fingerprint.
nonisolated final class CertPinStore: @unchecked Sendable {
    static let shared = CertPinStore()

    private let defaultsKey = "certPins.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var pins: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pins = (defaults.dictionary(forKey: "certPins.v1") as? [String: String]) ?? [:]
    }

    func pin(for host: String) -> String? {
        lock.withLock { pins[host.lowercased()] }
    }

    func setPin(_ fingerprint: String, for host: String) {
        lock.withLock {
            pins[host.lowercased()] = fingerprint
            defaults.set(pins, forKey: defaultsKey)
        }
    }

    func removePin(for host: String) {
        lock.withLock {
            pins[host.lowercased()] = nil
            defaults.set(pins, forKey: defaultsKey)
        }
    }
}
