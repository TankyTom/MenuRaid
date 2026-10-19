import Foundation
import Network

/// Emits a value whenever the Mac's network setup changes (Wi-Fi network, Ethernet, VPN or Tailscale up/down).
/// This is how MenuRaid notices you've arrived home or left, without needing the Wi-Fi name
/// (which needs Location permission on macOS 14+ and doesn't work on Ethernet).
final class NetworkPathObserver: @unchecked Sendable {
    let changes: AsyncStream<Void>

    private let monitor = NWPathMonitor()

    init() {
        var continuation: AsyncStream<Void>.Continuation!
        changes = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        let output = continuation!

        var lastSignature: String?
        monitor.pathUpdateHandler = { path in
            let interfaces = path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            let signature = "\(path.status)|\(interfaces)"
            defer { lastSignature = signature }
            // The first callback only reports the starting state, not a change.
            guard let previous = lastSignature, previous != signature else { return }
            output.yield()
        }
        monitor.start(queue: DispatchQueue(label: "MenuRaid.NetworkPathObserver"))
    }

    deinit {
        monitor.cancel()
    }
}
