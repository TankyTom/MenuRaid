import Foundation
import Network

/// Emits a value whenever the Mac's network setup changes (Wi-Fi network, Ethernet, VPN or Tailscale up/down).
/// This is how MenuRaid notices you've arrived home or left, without needing the Wi-Fi name
/// (which needs Location permission on macOS 14+ and doesn't work on Ethernet).
final class NetworkPathObserver: @unchecked Sendable {
    let changes: AsyncStream<Void>

    private let monitor = NWPathMonitor()

    /// The last network setup seen. The monitor calls back on its own queue, so access is guarded.
    private nonisolated final class Signature: @unchecked Sendable {
        private let lock = NSLock()
        private var last: String?

        /// Records the new signature; true only if it differs from a previous one (the first report is just the start state).
        func changed(to new: String) -> Bool {
            lock.withLock {
                defer { last = new }
                guard let last else { return false }
                return last != new
            }
        }
    }

    init() {
        var continuation: AsyncStream<Void>.Continuation!
        changes = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        let output = continuation!
        let signature = Signature()

        monitor.pathUpdateHandler = { path in
            let interfaces = path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            if signature.changed(to: "\(path.status)|\(interfaces)") { output.yield() }
        }
        monitor.start(queue: DispatchQueue(label: "MenuRaid.NetworkPathObserver"))
    }

    deinit {
        monitor.cancel()
    }
}
